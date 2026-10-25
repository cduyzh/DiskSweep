import Foundation

/// 单个文件或符号链接目标的真实元数据快照。
/// `size` 为逻辑大小（与 Finder 列表“大小”一致）；`allocatedSize` 为 APFS 实际分配，
/// 克隆与压缩文件两者可能不同。
public struct FileEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let size: UInt64
    public let allocatedSize: UInt64?
    public let modifiedAt: Date?
    public let createdAt: Date?
    public let inode: UInt64?
    public let linkCount: Int?
    public let isSymbolicLink: Bool

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var path: String { url.path }
    public var isHardlink: Bool { (linkCount ?? 1) > 1 }
    public var directory: String { url.deletingLastPathComponent().path }

    public init(url: URL, size: UInt64, allocatedSize: UInt64?, modifiedAt: Date?,
                createdAt: Date?, inode: UInt64?, linkCount: Int, isSymbolicLink: Bool) {
        self.url = url
        self.size = size
        self.allocatedSize = allocatedSize
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.inode = inode
        self.linkCount = linkCount
        self.isSymbolicLink = isSymbolicLink
    }
}

/// 目录树节点：体积为目录内所有普通文件（含子目录）的逻辑大小聚合。
/// 同一扫描内，多硬链接的文件只按一个 inode 计一次。
public struct DirectoryNode: Identifiable, Sendable {
    public let url: URL
    public let name: String
    public let depth: Int
    public var size: UInt64
    public var fileCount: Int
    public var directoryCount: Int
    public var children: [DirectoryNode]

    public var id: String { url.path }
    public var path: String { url.path }

    public init(url: URL, depth: Int) {
        self.url = url
        self.name = url.lastPathComponent
        self.depth = depth
        self.size = 0
        self.fileCount = 0
        self.directoryCount = 0
        self.children = []
    }
}

/// 挂载卷信息。容量采用系统报告口径，APFS 共享空间与 Finder 可能不同。
public struct VolumeInfo: Identifiable, Sendable {
    public let name: String
    public let mountPoint: URL
    public let totalBytes: UInt64
    public let availableBytes: UInt64
    public let isInternal: Bool
    public let isSystem: Bool
    public let isEjectable: Bool
    public let fileSystemType: String?

    public var id: String { mountPoint.path }
    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
}

/// 扫描阶段。全部阶段均为只读；删除属于显式的后续操作。
public enum ScanStage: Equatable, Sendable {
    case idle
    case enumerating
    case hashing
    case finishedAt(Date)
    case cancelled
    case failed(String)

    public var isRunning: Bool {
        self == .enumerating || self == .hashing
    }
}

/// 扫描进度快照，由后台线程节流上报。
public struct ScanProgress: Sendable {
    public var stage: ScanStage
    public var filesExamined: Int
    public var bytesExamined: UInt64
    public var directoriesExamined: Int
    public var currentPath: String
    public var hashCandidatesDone: Int
    public var hashCandidatesTotal: Int

    public init(stage: ScanStage = .idle, filesExamined: Int = 0, bytesExamined: UInt64 = 0,
                directoriesExamined: Int = 0, currentPath: String = "",
                hashCandidatesDone: Int = 0, hashCandidatesTotal: Int = 0) {
        self.stage = stage
        self.filesExamined = filesExamined
        self.bytesExamined = bytesExamined
        self.directoriesExamined = directoriesExamined
        self.currentPath = currentPath
        self.hashCandidatesDone = hashCandidatesDone
        self.hashCandidatesTotal = hashCandidatesTotal
    }
}

/// 扫描选项。
public struct ScanOptions: Sendable {
    public var scanRoot: URL
    /// 进入重复检测的最小文件体积，默认 1 MiB。
    public var minDuplicateSize: UInt64
    /// 大文件列表的最小体积，默认 100 MiB。
    public var largeFileThreshold: UInt64
    /// 忽略隐藏文件与目录（Finder 隐藏口径：以 “.” 开头）。
    public var skipHidden: Bool
    /// 目录树展示时每层保留的最大子目录数量。
    public var treeChildLimit: Int
    /// 默认排除的目录（备份、系统数据库等不适合清理的位置）。
    public var excludedPaths: Set<String>

    public init(scanRoot: URL = URL(fileURLWithPath: NSHomeDirectory()),
                minDuplicateSize: UInt64 = 1 << 20,
                largeFileThreshold: UInt64 = 100 << 20,
                skipHidden: Bool = false,
                treeChildLimit: Int = 12,
                excludedPaths: Set<String> = []) {
        self.scanRoot = scanRoot
        self.minDuplicateSize = minDuplicateSize
        self.largeFileThreshold = largeFileThreshold
        self.skipHidden = skipHidden
        self.treeChildLimit = treeChildLimit
        self.excludedPaths = excludedPaths
    }

    public static let defaultExclusions: Set<String> = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple",
        NSHomeDirectory() + "/Library/Mobile Documents",
    ]
}

/// 一次完整扫描的结果：目录树、候选文件、统计与不可读路径。
public struct ScanResult: Sendable {
    public let root: DirectoryNode
    public let rootURL: URL
    public let candidates: [FileEntry]
    public let totalFiles: Int
    public let totalDirectories: Int
    public let totalLogicalBytes: UInt64
    public let hardlinkSkipped: Int
    public let symlinkSkipped: Int
    public let inaccessiblePaths: [String]
    public let startedAt: Date
    public let finishedAt: Date

    /// 大文件列表：候选中超过阈值的文件按体积降序。
    public func largeFiles(threshold: UInt64) -> [FileEntry] {
        candidates.filter { $0.size >= threshold }.sorted { $0.size > $1.size }
    }

    public var scannedDuration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
}

/// 重复文件组。`files` 为全量哈希一致的真实路径；
/// 同组内共享 inode 的路径是硬链接副本，删除它们不会立即释放物理空间。
public struct DuplicateGroup: Identifiable, Sendable {
    public let contentDigest: String
    public let fileSize: UInt64
    public let files: [FileEntry]

    public init(contentDigest: String, fileSize: UInt64, files: [FileEntry]) {
        self.contentDigest = contentDigest
        self.fileSize = fileSize
        self.files = files
    }

    public var id: String { contentDigest }
    /// 不同的 inode 数；inode 未知的文件按各自独立计算，避免把未知当成共享。
    public var distinctInodes: Int {
        let known = Set(files.compactMap(\.inode))
        let unknown = files.filter { $0.inode == nil }.count
        return known.count + unknown
    }
    /// 可回收估计：保留一个副本时，按不同 inode 数计算的逻辑体积。
    public var reclaimableBytes: UInt64 {
        fileSize * UInt64(max(distinctInodes - 1, 0))
    }
    public var containsHardlinks: Bool { distinctInodes < files.count }
}

/// 删除方式。默认推荐废纸篓；永久删除需要用户显式选择。
public enum DeletionMode: String, CaseIterable, Sendable {
    case trash = "移入废纸篓"
    case permanent = "永久删除"

    public var isRecoverable: Bool { self == .trash }
}

/// 单个文件的删除结果。
public struct DeletionOutcome: Identifiable, Sendable {
    public enum Ending: Equatable, Sendable {
        case movedToTrash
        case deleted
        case skippedChanged
        case skippedProtected
        case failed(String)
    }

    public let url: URL
    public let ending: Ending
    public var id: String { url.path }

    public var succeeded: Bool { ending == .movedToTrash || ending == .deleted }
}
