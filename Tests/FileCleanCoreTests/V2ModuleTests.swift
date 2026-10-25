import XCTest
@testable import FileCleanCore

/// v0.2 新模块测试：哈希缓存、标识符残留匹配、treemap 布局、更新检查与快照解析。
final class V2ModuleTests: XCTestCase {
    var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("fileclean-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    // MARK: 哈希缓存

    func testHashCacheRoundTripAndInvalidation() throws {
        let cache = try HashCache(url: workspace.appendingPathComponent("cache.sqlite3"))
        cache.save(path: "/tmp/a.bin", size: 100, mtimeNs: 111, sample: "s1", full: "f1")
        XCTAssertEqual(cache.fullDigest(path: "/tmp/a.bin", size: 100, mtimeNs: 111), "f1")
        // 大小或时间变化 → 键不匹配。
        XCTAssertNil(cache.fullDigest(path: "/tmp/a.bin", size: 200, mtimeNs: 111))
        XCTAssertNil(cache.fullDigest(path: "/tmp/a.bin", size: 100, mtimeNs: 222))
        // UPSERT 覆盖。
        cache.save(path: "/tmp/a.bin", size: 100, mtimeNs: 222, sample: nil, full: "f2")
        XCTAssertEqual(cache.fullDigest(path: "/tmp/a.bin", size: 100, mtimeNs: 222), "f2")
        XCTAssertEqual(cache.entryCount(), 1)
    }

    func testHashCachePruneRemovesStaleEntries() throws {
        let cache = try HashCache(url: workspace.appendingPathComponent("cache.sqlite3"))
        cache.save(path: "/keep", size: 1, mtimeNs: 1, sample: nil, full: "k")
        cache.save(path: "/gone", size: 2, mtimeNs: 2, sample: nil, full: "g")
        let removed = cache.prune(validKeys: [(path: "/keep", size: 1, mtimeNs: 1)])
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(cache.entryCount(), 1)
        XCTAssertNotNil(cache.fullDigest(path: "/keep", size: 1, mtimeNs: 1))
        XCTAssertNil(cache.fullDigest(path: "/gone", size: 2, mtimeNs: 2))
    }

    func testDuplicateFinderUsesCacheOnSecondRun() throws {
        let payload = Data(repeating: 4, count: 2048)
        let one = workspace.appendingPathComponent("one.bin")
        let two = workspace.appendingPathComponent("two.bin")
        try payload.write(to: one)
        try payload.write(to: two)
        let keys: [UInt64: Date] = [2048: Date()]
        _ = keys
        let entry = { (url: URL) in
            FileEntry(url: url, size: 2048, allocatedSize: nil, modifiedAt: nil,
                      createdAt: nil, inode: nil, linkCount: 1, isSymbolicLink: false)
        }
        let files = [entry(one), entry(two)]
        let cache = try HashCache(url: workspace.appendingPathComponent("dup.sqlite3"))
        let first = DuplicateFinder.findGroups(in: files, minSize: 1, cache: cache)
        XCTAssertEqual(first.groups.count, 1)
        XCTAssertEqual(first.cachedBytes, 0)
        let second = DuplicateFinder.findGroups(in: files, minSize: 1, cache: cache)
        XCTAssertEqual(second.groups.count, 1)
        XCTAssertEqual(second.cachedBytes, 4096, "第二次运行应全部命中缓存")
        XCTAssertEqual(second.hashedBytes, 0)
    }

    // MARK: 应用清单与残留匹配

    private func makeFakeApp(bundleID: String, name: String) throws -> InstalledApp {
        let appURL = workspace.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": "1.2.0",
            "CFBundleVersion": "120",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Info.plist"))
        guard let app = AppCatalog.parse(bundleURL: appURL.deletingLastPathComponent()) else {
            throw NSError(domain: "test", code: 1)
        }
        return app
    }

    func testParseFakeAppBundle() throws {
        let app = try makeFakeApp(bundleID: "com.acme.mytool", name: "MyTool")
        XCTAssertEqual(app.bundleID, "com.acme.mytool")
        XCTAssertEqual(app.version, "1.2.0")
        XCTAssertFalse(app.isSystem)
        XCTAssertTrue(app.isUninstallable)
    }

    func testIdentifiersIncludeNormalizedForms() throws {
        let app = try makeFakeApp(bundleID: "com.knollsoft.Rectangle", name: "Rectangle 120.0")
        let identifiers = ResidualFinder.identifiers(for: app)
        XCTAssertTrue(identifiers.contains("comknollsoftrectangle"), "完整 bundle ID")
        XCTAssertTrue(identifiers.contains("knollsoftrectangle"), "后两段合并")
        XCTAssertTrue(identifiers.contains("rectangle1200") || identifiers.contains("rectangle"),
                      "应用名去版本号")
    }

    func testResidualMatchingSensitivity() throws {
        let app = try makeFakeApp(bundleID: "com.acme.mytool", name: "MyTool")
        let identifiers = ResidualFinder.identifiers(for: app)
        XCTAssertTrue(ResidualFinder.match(
            entry: URL(fileURLWithPath: "/x/com.acme.mytool.plist"),
            identifiers: identifiers, sensitivity: .strict))
        XCTAssertTrue(ResidualFinder.match(
            entry: URL(fileURLWithPath: "/x/MyTool"),
            identifiers: identifiers, sensitivity: .strict))
        // 点分后缀剥掉扩展名后即精确命中 bundle ID：严格档视为归属（helper 语义）。
        XCTAssertTrue(ResidualFinder.match(
            entry: URL(fileURLWithPath: "/x/com.acme.mytool.helper"),
            identifiers: identifiers, sensitivity: .strict))
        // 纯子串命中：严格档不认，增强档认。
        let partial = URL(fileURLWithPath: "/x/mytool-backup-data")
        XCTAssertFalse(ResidualFinder.match(entry: partial, identifiers: identifiers, sensitivity: .strict))
        XCTAssertTrue(ResidualFinder.match(entry: partial, identifiers: identifiers, sensitivity: .enhanced))
        XCTAssertFalse(ResidualFinder.match(
            entry: URL(fileURLWithPath: "/x/unrelated"),
            identifiers: identifiers, sensitivity: .enhanced))
    }

    func testSystemAppsCannotUninstall() throws {
        let systemApp = InstalledApp(
            bundleURL: URL(fileURLWithPath: "/System/Applications/Mail.app"),
            bundleID: "com.apple.mail", name: "Mail", version: "1", build: "1",
            isSystem: true, isFromAppStore: false, sparkleFeedURL: nil)
        XCTAssertFalse(systemApp.isUninstallable)
        XCTAssertNotNil(AppUninstaller.uninstallBlockedReason(for: systemApp))

        let appleApp = InstalledApp(
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            bundleID: "com.apple.Safari", name: "Safari", version: "1", build: "1",
            isSystem: false, isFromAppStore: false, sparkleFeedURL: nil)
        XCTAssertFalse(appleApp.isUninstallable)
    }

    // MARK: treemap 布局

    private func node(_ path: String, size: UInt64, depth: Int = 0) -> DirectoryNode {
        var item = DirectoryNode(url: URL(fileURLWithPath: path), depth: depth)
        item.size = size
        item.fileCount = 1
        return item
    }

    func testTreemapTilesCoverUnitArea() {
        var root = DirectoryNode(url: URL(fileURLWithPath: "/scan"), depth: 0)
        root.children = [
            node("/scan/a", size: 50), node("/scan/b", size: 30),
            node("/scan/c", size: 15), node("/scan/d", size: 5),
        ]
        root.size = 100
        let tiles = TreemapLayout.tiles(for: root)
        XCTAssertEqual(tiles.count, 4)
        let area = tiles.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
        XCTAssertEqual(area, 1.0, accuracy: 0.001, "区块面积和应归一化为 1")
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.rect.minX, 0)
            XCTAssertLessThanOrEqual(tile.rect.maxX, 1.0001)
            XCTAssertLessThanOrEqual(tile.rect.maxY, 1.0001)
            XCTAssertGreaterThan(tile.rect.width * tile.rect.height, 0)
        }
    }

    func testTreemapMergesOverflowIntoOther() {
        var root = DirectoryNode(url: URL(fileURLWithPath: "/scan"), depth: 0)
        root.children = (0..<50).map { node("/scan/n\($0)", size: UInt64($0 + 1)) }
        root.size = 1275
        let tiles = TreemapLayout.tiles(for: root, childLimit: 40)
        XCTAssertEqual(tiles.count, 41, "40 个保留 + 1 个“其他”")
        XCTAssertTrue(tiles.contains { $0.name.hasPrefix("其他") })
    }

    // MARK: 更新检查

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.2.0", olderThan: "1.10.0"), "数值比较而非字典序")
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0", olderThan: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", olderThan: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isVersion("1.3", olderThan: "1.2.9"))
    }

    func testAppcastParsing() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>MyTool Changelog</title>
            <item><title>Version 1.1</title>
              <enclosure url="https://example.com/MyTool-1.1.zip"
                         sparkle:version="110" sparkle:shortVersionString="1.1" length="123"/>
            </item>
          </channel>
        </rss>
        """
        XCTAssertEqual(UpdateChecker.parseAppcast(Data(xml.utf8)), "1.1", "优先 shortVersionString")
    }

    // MARK: 快照解析

    func testSnapshotDisplayNameParsing() {
        let snapshot = LocalSnapshot(rawName: "com.apple.TimeMachine.2026-10-24-101112.backup", volume: "/")
        XCTAssertEqual(snapshot.displayDate, "2026-10-24 10:11:12")
        XCTAssertEqual(snapshot.id, "/:com.apple.TimeMachine.2026-10-24-101112.backup")
        let weird = LocalSnapshot(rawName: "garbage", volume: "/")
        XCTAssertEqual(weird.displayDate, "garbage", "无法解析时原样返回")
    }
}
