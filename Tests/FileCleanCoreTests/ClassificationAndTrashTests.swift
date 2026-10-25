import XCTest
@testable import FileCleanCore

final class ClassificationAndTrashTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("fileclean-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: workspace) }

    private func file(_ name: String, size: UInt64, modified: Date? = nil) -> FileEntry {
        FileEntry(url: workspace.appendingPathComponent(name), size: size, allocatedSize: nil,
                  modifiedAt: modified, createdAt: nil, inode: nil, linkCount: 1, isSymbolicLink: false)
    }

    func testClassificationCoversCommonAndSpecializedFormats() {
        let cases: [(String, FileCategory)] = [
            ("clip.MOV", .video), ("movie.mkv", .video), ("track.flac", .audio),
            ("design.psd", .image), ("photo.HEIC", .image), ("report.pdf", .document),
            ("sheet.xlsx", .document), ("archive.tar.gz", .archive), ("archive.7z", .archive),
            ("macOS.dmg", .installer), ("image.iso", .installer), ("disk.qcow2", .virtualMachine),
            ("disk.vmdk", .virtualMachine), ("model.gguf", .development), ("cache.sqlite3", .development),
            ("README", .other), ("opaque.unrecognized-fileclean-format", .other),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(file(name, size: 1).category, expected, name)
        }
    }

    func testCategoryTotalsAccountForEveryFileOnce() {
        let files = [file("a.mov", size: 100), file("b.MP4", size: 200), file("z.unknown", size: 50), file("d.zip", size: 25)]
        let summaries = FileCategorySummary.summarize(files)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.count }, files.count)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.bytes }, 375)
        XCTAssertEqual(summaries.first { $0.category == .video }?.count, 2)
        XCTAssertEqual(summaries.first { $0.category == .video }?.bytes, 300)
        XCTAssertEqual(summaries.map(\.category), [.video, .archive, .other])
        XCTAssertTrue(FileCategorySummary.summarize([]).isEmpty)
    }

    func testCombinedCategoryAndPathSearchAndSort() {
        let files = [file("work/clip10.MOV", size: 100, modified: Date(timeIntervalSince1970: 3)),
                     file("work/clip2.mov", size: 200, modified: Date(timeIntervalSince1970: 2)),
                     file("private/clip1.mov", size: 300), file("work/clip.mp3", size: 900)]
        XCTAssertEqual(LargeFileSort.size.filter(files, category: .video, query: " WORK/ ").map(\.size), [200, 100])
        XCTAssertEqual(LargeFileSort.name.filter(files, category: .video, query: "work/").map(\.name), ["clip2.mov", "clip10.MOV"])
        XCTAssertEqual(LargeFileSort.modified.filter(files, category: .video, query: "").first?.size, 100)
        XCTAssertTrue(LargeFileSort.size.filter(files, category: .document, query: "").isEmpty)
    }

    func testLargeFilesCollectedBelowDuplicateThreshold() throws {
        let url = workspace.appendingPathComponent("movie.mov")
        try Data(repeating: 1, count: 20).write(to: url)
        let result = try DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 100, largeFileThreshold: 10)).start()
        XCTAssertEqual(result.largeFiles(threshold: 10).map(\.name), ["movie.mov"])
        XCTAssertTrue(DuplicateFinder.findGroups(in: result.candidates, minSize: 100).groups.isEmpty)
    }

    func testTrashFailureNeverFallsBackToPermanentDeletion() throws {
        let url = workspace.appendingPathComponent("keep.bin")
        let payload = Data("must survive a trash failure".utf8)
        try payload.write(to: url)
        var attemptedURL: URL?
        let outcome = FileDeleter.performAction(url) { requested in
            attemptedURL = requested
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(attemptedURL, url)
        XCTAssertFalse(outcome.succeeded)
        if case .failed(let message) = outcome.ending { XCTAssertTrue(message.contains("未执行永久删除")) }
        else { XCTFail("Expected explicit failure") }
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testTrashRequiresFileToLeaveOriginalLocation() throws {
        let url = workspace.appendingPathComponent("not-moved.bin")
        try Data([1]).write(to: url)
        let outcome = FileDeleter.performAction(url) { _ in }
        XCTAssertFalse(outcome.succeeded, "A no-op trash implementation must not report success")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSystemTrashCanRestoreOurFixture() throws {
        // This test creates and restores only its own uniquely named fixture.
        let url = workspace.appendingPathComponent("fileclean-trash-test-\(UUID().uuidString).txt")
        let payload = Data("recoverable fixture".utf8)
        try payload.write(to: url)
        var destination: NSURL?
        defer {
            if let destination { try? FileManager.default.moveItem(at: destination as URL, to: url) }
        }
        let outcome = FileDeleter.performAction(url) { source in
            try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
        }
        XCTAssertEqual(outcome.ending, .movedToTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let trashed = try XCTUnwrap(destination) as URL
        XCTAssertEqual(try Data(contentsOf: trashed), payload)
        try FileManager.default.moveItem(at: trashed, to: url)
        destination = nil
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testScannedAPFSIdentityCanBeVerifiedForAction() throws {
        let url = workspace.appendingPathComponent("verified.bin")
        try Data(repeating: 1, count: 128).write(to: url)
        let result = try DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1)).start()
        let entry = try XCTUnwrap(result.candidates.first)
        XCTAssertNotNil(entry.inode)
        // Only this temporary fixture is removed. Exercises APFS NSData identity conversion.
        XCTAssertEqual(FileDeleter.delete([entry], mode: .permanent).first?.ending, .deleted)
    }

    func testDefaultEntryDeletionRejectsStaleSnapshot() throws {
        let url = workspace.appendingPathComponent("changed.bin")
        try Data(repeating: 1, count: 30).write(to: url)
        let result = try DiskScanner(options: ScanOptions(scanRoot: workspace, minDuplicateSize: 1)).start()
        try Data(repeating: 2, count: 60).write(to: url)
        XCTAssertEqual(FileDeleter.delete(result.candidates).first?.ending, .skippedChanged)
        XCTAssertEqual(try Data(contentsOf: url).count, 60)
    }
}
