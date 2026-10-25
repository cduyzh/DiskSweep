import Foundation

/// 磁盘与目录扫描引擎。只读：枚举真实文件元数据，聚合目录体积，
/// 收集重复检测候选；不做任何修改动作。
public final class DiskScanner: @unchecked Sendable {
    private let options: ScanOptions
    private let progressSink: @Sendable (ScanProgress) -> Void
    private let lock = NSLock()
    private var cancelledFlag = false

    private var progress = ScanProgress(stage: .idle)
    private var lastProgressAt = Date.distantPast

    /// 默认排除的包类型：系统与备份类目录内部不适合普通清理。
    private static let packageExclusions: Set<String> = [
        "Photos Library.photoslibrary", "Music Library.musiclibrary",
        "Aperture Library.aplibrary", "Final Cut Library.fcpbundle",
    ]

    public init(options: ScanOptions, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) {
        self.options = options
        self.progressSink = progress
    }

    public func cancel() {
        lock.lock(); cancelledFlag = true; lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelledFlag
    }

    /// 已挂载的可读卷。快照口径，APFS 家族容器共享空间可能与 Finder 显示不同。
    public static func mountedVolumes() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRootFileSystemKey,
            .volumeIsAutomountedKey, .volumeLocalizedFormatDescriptionKey,
        ]
        let urls = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys)) ?? [])
            .filter { !$0.path.hasPrefix("/System/Volumes/") || $0.path == "/System/Volumes/Data" }
            .filter { !$0.path.hasPrefix("/private/") }
        var volumes: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard let name = values.volumeName else { continue }
            let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
            let available = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) } ?? 0
            // 容量信息缺失的虚拟卷（如 VM）不参与展示。
            guard total > 0 else { continue }
            volumes.append(VolumeInfo(
                name: name,
                mountPoint: url,
                totalBytes: total,
                availableBytes: available,
                isInternal: values.volumeIsInternal ?? false,
                isSystem: values.volumeIsRootFileSystem ?? false || url.path == "/",
                isEjectable: values.volumeIsEjectable ?? false,
                fileSystemType: values.volumeLocalizedFormatDescription,
            ))
        }
        return volumes
    }

    /// 执行完整扫描。同步方法：调用方应在后台队列运行（见 `Background.run`）。
    public func start() throws -> ScanResult {
        let startedAt = Date()
        let rootURL = options.scanRoot.standardizedFileURL
        var root = DirectoryNode(url: rootURL, depth: 0)
        var inaccessible: [String] = []
        var candidates: [FileEntry] = []
        var hardlinkSkipped = 0
        var symlinkSkipped = 0
        var seenInodes = Set<UInt64>()
        let fileManager = FileManager.default

        func shouldExclude(_ url: URL) -> Bool {
            let path = url.path
            guard !options.excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return true }
            if DiskScanner.packageExclusions.contains(url.lastPathComponent) { return true }
            return false
        }

        func emitProgress(stage: ScanStage? = nil) {
            if let stage { progress.stage = stage }
            let now = Date()
            guard now.timeIntervalSince(lastProgressAt) > 0.1 || stage?.isRunning != true else { return }
            lastProgressAt = now
            progressSink(progress)
        }

        emitProgress(stage: .enumerating)

        // 显式递归深度受 PATH_MAX 自然约束；每层一个栈帧，风险可控。
        func walk(_ url: URL, _ depth: Int, _ node: inout DirectoryNode) {
            if isCancelled { return }
            progress.directoriesExamined += 1
            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(DiskScanner.metadataKeys))
            } catch {
                inaccessible.append(url.path)
                return
            }
            var children: [DirectoryNode] = []
            for child in contents {
                if isCancelled { return }
                progress.currentPath = child.path
                guard let values = try? child.resourceValues(forKeys: DiskScanner.metadataKeys) else { continue }
                if options.skipHidden && (values.isHidden ?? false || child.lastPathComponent.hasPrefix(".")) { continue }

                if values.isDirectory ?? false {
                    if shouldExclude(child) { continue }
                    var childNode = DirectoryNode(url: child, depth: depth + 1)
                    progress.directoriesExamined += 1
                    walk(child, depth + 1, &childNode)
                    node.size += childNode.size
                    node.fileCount += childNode.fileCount
                    node.directoryCount += childNode.directoryCount + 1
                    children.append(childNode)
                } else if values.isRegularFile ?? false || values.isSymbolicLink ?? false {
                    let entry = FileEntry(
                        url: child,
                        size: UInt64(max(values.fileSize ?? 0, 0)),
                        allocatedSize: values.fileAllocatedSize.map { UInt64(max($0, 0)) },
                        modifiedAt: values.contentModificationDate,
                        createdAt: values.creationDate,
                        inode: DiskScanner.inodeNumber(values.fileResourceIdentifier),
                        linkCount: DiskScanner.linkCount(of: child),
                        isSymbolicLink: values.isSymbolicLink ?? false,
                    )
                    if entry.isSymbolicLink {
                        // 符号链接不计体积、不做重复候选，避免环与重复计数。
                        symlinkSkipped += 1
                        continue
                    }
                    progress.filesExamined += 1
                    node.fileCount += 1
                    // 多硬链接按路径计数，但体积与候选只在首次遇到该 inode 时计入。
                    if entry.isHardlink, let inode = entry.inode {
                        if seenInodes.contains(inode) {
                            hardlinkSkipped += 1
                            continue
                        }
                        seenInodes.insert(inode)
                    }
                    progress.bytesExamined += entry.size
                    node.size += entry.size
                    if entry.size >= min(options.minDuplicateSize, options.largeFileThreshold) {
                        candidates.append(entry)
                    }
                    if progress.filesExamined % 256 == 0 { emitProgress() }
                }
            }
            node.children = children.sorted { $0.size > $1.size }
        }

        walk(rootURL, 0, &root)

        if isCancelled {
            progress.stage = .cancelled
            progressSink(progress)
            return ScanResult(
                root: root, rootURL: rootURL, candidates: [], totalFiles: 0, totalDirectories: 0,
                totalLogicalBytes: 0, hardlinkSkipped: 0, symlinkSkipped: 0,
                inaccessiblePaths: inaccessible, startedAt: startedAt, finishedAt: Date())
        }

        let result = ScanResult(
            root: root,
            rootURL: rootURL,
            candidates: candidates,
            totalFiles: root.fileCount,
            totalDirectories: root.directoryCount,
            totalLogicalBytes: root.size,
            hardlinkSkipped: hardlinkSkipped,
            symlinkSkipped: symlinkSkipped,
            inaccessiblePaths: inaccessible,
            startedAt: startedAt,
            finishedAt: Date())
        progress.stage = .finishedAt(Date())
        progressSink(progress)
        return result
    }

    static let metadataKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
        .fileResourceIdentifierKey,
    ]

    /// fileResourceIdentifier 在 APFS 上是 NSData、HFS+ 上可能是 NSNumber；
    /// 统一折算为 64 位数值用于硬链接去重（仅在单卷扫描内比较，无需全局唯一）。
    static func inodeNumber(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let data = value as? Data, data.count >= 8 {
            return data.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        return nil
    }

    /// URL 资源键不暴露硬链接数，这里用 POSIX stat 读取 st_nlink。
    static func linkCount(of url: URL) -> Int {
        var status = stat()
        return stat(url.path, &status) == 0 ? Int(status.st_nlink) : 1
    }
}

/// 把阻塞式扫描调度到全局工具队列，避免占用 Swift 协作线程。
public enum Background {
    public static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
