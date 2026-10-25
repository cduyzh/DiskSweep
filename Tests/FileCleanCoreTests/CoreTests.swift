import XCTest
@testable import FileCleanCore

/// 用真实临时目录构造文件、硬链接与符号链接，验证扫描聚合与重复检测管线。
final class FileCleanCoreTests: XCTestCase {
    var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("fileclean-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    @discardableResult
    private func write(_ relative: String, _ content: Data) throws -> URL {
        let url = workspace.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
        return url
    }

    private func entry(at url: URL, size: UInt64) -> FileEntry {
        FileEntry(url: url, size: size, allocatedSize: nil, modifiedAt: nil, createdAt: nil,
                  inode: nil, linkCount: 1, isSymbolicLink: false)
    }

    // MARK: 扫描聚合

    func testScanAggregatesSizesAndCounts() throws {
        try write("a/one.bin", Data(repeating: 1, count: 4096))
        try write("a/two.bin", Data(repeating: 2, count: 2048))
        try write("b/three.bin", Data(repeating: 3, count: 1024))

        let scanner = DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1))
        let result = try scanner.start()

        XCTAssertEqual(result.totalFiles, 3)
        XCTAssertEqual(result.root.size, 4096 + 2048 + 1024)
        XCTAssertEqual(result.root.directoryCount, 2)
        let names = result.root.children.map(\.name)
        XCTAssertTrue(names.contains("a") && names.contains("b"))
        let a = result.root.children.first { $0.name == "a" }
        XCTAssertEqual(a?.size, 4096 + 2048)
        // minDuplicateSize=1 时全部文件进入候选。
        XCTAssertEqual(result.candidates.count, 3)
    }

    func testSymlinksAreSkippedAndNotCounted() throws {
        try write("real.bin", Data(repeating: 9, count: 512))
        try FileManager.default.createSymbolicLink(
            at: workspace.appendingPathComponent("link.bin"),
            withDestinationURL: workspace.appendingPathComponent("real.bin"))

        let scanner = DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1))
        let result = try scanner.start()

        XCTAssertEqual(result.totalFiles, 1)
        XCTAssertEqual(result.root.size, 512)
        XCTAssertEqual(result.symlinkSkipped, 1)
        XCTAssertEqual(result.candidates.count, 1)
    }

    func testHardlinkCountedOnce() throws {
        let original = try write("one.bin", Data(repeating: 7, count: 4096))
        try FileManager.default.linkItem(at: original, to: workspace.appendingPathComponent("two.bin"))

        let scanner = DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1))
        let result = try scanner.start()

        // 两个路径、一个 inode：体积只计一次，候选只留一个。
        XCTAssertEqual(result.totalFiles, 2)
        XCTAssertEqual(result.root.size, 4096)
        XCTAssertEqual(result.hardlinkSkipped, 1)
        XCTAssertEqual(result.candidates.count, 1)
    }

    func testCancellationYieldsEmptyCandidates() throws {
        try write("deep/one.bin", Data(repeating: 1, count: 128))
        let lock = NSLock()
        var observedStages: [ScanStage] = []
        let scanner = DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1)) { snapshot in
            lock.lock(); observedStages.append(snapshot.stage); lock.unlock()
        }
        scanner.cancel()
        let result = try scanner.start()
        XCTAssertEqual(result.candidates.count, 0)
        lock.lock()
        let cancelled = observedStages.contains { $0 == .cancelled }
        lock.unlock()
        XCTAssertTrue(cancelled, "取消后的进度回调应包含 cancelled 阶段")
    }

    // MARK: 重复检测

    func testDuplicateFinderGroupsIdenticalContent() throws {
        let payload = Data("cduyzh-fileclean-duplicate-payload".utf8)
        try write("a/copy1.bin", payload)
        try write("b/copy2.bin", payload)
        try write("c/other.bin", Data("different-content-of-same-length----".utf8))

        let files = [
            entry(at: workspace.appendingPathComponent("a/copy1.bin"), size: UInt64(payload.count)),
            entry(at: workspace.appendingPathComponent("b/copy2.bin"), size: UInt64(payload.count)),
            entry(at: workspace.appendingPathComponent("c/other.bin"), size: UInt64(payload.count)),
        ]
        let outcome = DuplicateFinder.findGroups(in: files, minSize: 1)

        XCTAssertEqual(outcome.groups.count, 1)
        let group = try XCTUnwrap(outcome.groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(group.fileSize, UInt64(payload.count))
        XCTAssertEqual(group.reclaimableBytes, UInt64(payload.count))
    }

    func testDuplicateFinderRespectsMinimumSize() throws {
        let payload = Data(repeating: 5, count: 2048)
        try write("x/copy1.bin", payload)
        try write("y/copy2.bin", payload)
        let files = [
            entry(at: workspace.appendingPathComponent("x/copy1.bin"), size: 2048),
            entry(at: workspace.appendingPathComponent("y/copy2.bin"), size: 2048),
        ]
        // 阈值高于文件体积：不进入检测。
        let outcome = DuplicateFinder.findGroups(in: files, minSize: 4096)
        XCTAssertEqual(outcome.groups.count, 0)
    }

    func testHardlinkGroupReclaimableUsesDistinctInodes() throws {
        let original = try write("h/one.bin", Data(repeating: 3, count: 4096))
        try FileManager.default.linkItem(at: original, to: workspace.appendingPathComponent("h/two.bin"))
        let inode = UInt64(777)
        let files = [
            FileEntry(url: original, size: 4096, allocatedSize: nil, modifiedAt: nil, createdAt: nil,
                      inode: inode, linkCount: 2, isSymbolicLink: false),
            FileEntry(url: workspace.appendingPathComponent("h/two.bin"), size: 4096, allocatedSize: nil,
                      modifiedAt: nil, createdAt: nil, inode: inode, linkCount: 2, isSymbolicLink: false),
        ]
        let outcome = DuplicateFinder.findGroups(in: files, minSize: 1)
        XCTAssertEqual(outcome.groups.count, 1)
        let group = outcome.groups[0]
        XCTAssertTrue(group.containsHardlinks)
        // 同一 inode 的两条路径：可回收为 0（删除一条硬链接不释放空间）。
        XCTAssertEqual(group.reclaimableBytes, 0)
    }

    // MARK: 删除保护与身份核对

    func testProtectedPathsAreRejected() {
        XCTAssertTrue(FileProtector.isProtected(URL(fileURLWithPath: "/")))
        XCTAssertTrue(FileProtector.isProtected(URL(fileURLWithPath: "/System/Library")))
        XCTAssertTrue(FileProtector.isProtected(URL(fileURLWithPath: "/usr/bin/ls")))
        XCTAssertTrue(FileProtector.isProtected(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Keychains/meta")))
        XCTAssertFalse(FileProtector.isProtected(URL(fileURLWithPath: NSHomeDirectory() + "/Documents/notes.txt")))
        // 测试目录中的普通文件不受保护。
        XCTAssertFalse(FileProtector.isProtected(URL(fileURLWithPath: workspace.path + "/a/one.bin")))
    }

    func testDeletionSkipsChangedFiles() throws {
        let url = try write("changed.bin", Data(repeating: 1, count: 256))
        let stale = entry(at: url, size: 256)
        // 删除前文件被改写：身份核对应拦截。
        try Data(repeating: 2, count: 999).write(to: url)
        let outcomes = FileDeleter.delete([stale], mode: .permanent)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].ending, .skippedChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPermanentDeletionRemovesVerifiedFile() throws {
        let url = try write("gone.bin", Data(repeating: 1, count: 128))
        let fresh = entry(at: url, size: 128)
        let outcomes = FileDeleter.delete([fresh], mode: .permanent)
        XCTAssertEqual(outcomes[0].ending, .deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: 卷信息

    func testMountedVolumesReadable() {
        let volumes = DiskScanner.mountedVolumes()
        XCTAssertTrue(volumes.contains { $0.mountPoint.path == "/" })
    }
}
