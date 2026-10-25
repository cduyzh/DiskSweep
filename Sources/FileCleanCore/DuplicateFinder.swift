import Foundation
import CryptoKit

/// 重复文件检测：经典三级过滤管线（体积分组 → 采样哈希 → 全量哈希）。
/// 1) 体积分组：不同大小的文件必然内容不同，零 I/O 排除绝大多数文件；
/// 2) 采样哈希：读取每个同尺寸候选的首段数据做 SHA-256 前缀比较；
/// 3) 全量哈希：仅对采样一致的候选读取整个文件做完整 SHA-256。
/// 只有走完全部三级且摘要一致的文件才归为重复组；不做模糊或概率匹配。
public enum DuplicateFinder {

    public struct Outcome: Sendable {
        public let groups: [DuplicateGroup]
        public let sampledBytes: UInt64
        public let hashedBytes: UInt64
        /// 命中缓存而免于全量读取的字节数。
        public let cachedBytes: UInt64
    }

    private static let chunkLength = 1 << 20

    public static func findGroups(
        in candidates: [FileEntry],
        minSize: UInt64,
        cache: HashCache? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) -> Outcome {
        let empty = Outcome(groups: [], sampledBytes: 0, hashedBytes: 0, cachedBytes: 0)
        // 第一级：体积分组，仅保留出现两次以上的尺寸。
        var bySize: [UInt64: [FileEntry]] = [:]
        for entry in candidates where entry.size >= minSize && !entry.isSymbolicLink {
            bySize[entry.size, default: []].append(entry)
        }
        let sizedGroups = bySize.values.filter { $0.count > 1 }.map { $0.sorted { $0.path < $1.path } }

        // 第二级：采样哈希（首段 + 大文件三点采样）。
        var sampledBytes: UInt64 = 0
        var sampleTasks: [(FileEntry, String)] = []
        for group in sizedGroups {
            if isCancelled() { return empty }
            for entry in group {
                let sample = readSample(entry: entry)
                sampledBytes += UInt64(sample?.count ?? 0)
                if let sample, !sample.isEmpty {
                    let digest = SHA256.hash(data: sample).map { String(format: "%02x", $0) }.joined()
                    sampleTasks.append((entry, digest))
                } else if sample != nil && entry.size == 0 {
                    // 同尺寸空文件：无数据可采样，用占位摘要参与分组，全量阶段自然判等。
                    sampleTasks.append((entry, "empty"))
                }
            }
        }

        var bySample: [String: [FileEntry]] = [:]
        for (entry, digest) in sampleTasks {
            bySample[digest, default: []].append(entry)
        }
        let sampleGroups = bySample.values.filter { $0.count > 1 }

        // 第三级：全量 SHA-256；未变化的文件优先复用持久化缓存。
        var hashedBytes: UInt64 = 0
        var cachedBytes: UInt64 = 0
        let total = sampleGroups.reduce(0) { $0 + $1.count }
        var done = 0
        var groups: [DuplicateGroup] = []
        for group in sampleGroups {
            if isCancelled() { return empty }
            var byDigest: [String: [FileEntry]] = [:]
            for entry in group {
                let mtime = HashCache.mtimeNanoseconds(entry.modifiedAt)
                if let cache, let digest = cache.fullDigest(path: entry.path, size: entry.size, mtimeNs: mtime) {
                    cachedBytes += entry.size
                    byDigest[digest, default: []].append(entry)
                } else if let digest = fullDigest(entry: entry, hashedBytes: &hashedBytes) {
                    cache?.save(path: entry.path, size: entry.size, mtimeNs: mtime, sample: nil, full: digest)
                    byDigest[digest, default: []].append(entry)
                }
                done += 1
                progress(done, total)
            }
            for (digest, files) in byDigest where files.count > 1 {
                groups.append(DuplicateGroup(contentDigest: digest, fileSize: files[0].size, files: files))
            }
        }
        return Outcome(
            groups: groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            sampledBytes: sampledBytes,
            hashedBytes: hashedBytes,
            cachedBytes: cachedBytes
        )
    }

    /// 读取采样数据；读取失败（权限、消失）返回 nil，该文件退出检测。
    /// 采样策略（跳过文件头 + 大文件三点采样）：
    /// - 小于 32 KiB 的文件整读；
    /// - 其他文件从偏移 16 KiB 起读 64 KiB（跳过常带元数据的文件头）；
    /// - 大于 3 MiB 的文件追加 25%、60%、末尾三个 1 MiB 采样点，
    ///   大媒体文件正文相同而头部不同的情况靠这三点拦截。
    private static func readSample(entry: FileEntry) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: entry.url) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        func read(at offset: UInt64, length: Int) -> Bool {
            guard length > 0 else { return true }
            guard offset < entry.size else { return true }
            do {
                try handle.seek(toOffset: offset)
                guard let chunk = try handle.read(upToCount: length), !chunk.isEmpty else { return false }
                data.append(chunk)
                return true
            } catch { return false }
        }
        let size = entry.size
        if size <= 32 * 1024 {
            guard read(at: 0, length: Int(size)) else { return nil }
        } else {
            guard read(at: 16 * 1024, length: 64 * 1024) else { return nil }
            if size > 3 << 20 {
                let meg = 1 << 20
                let points = [size / 4, size * 6 / 10, size > UInt64(meg) ? size - UInt64(meg) : 0]
                for point in points where read(at: point, length: meg) == false { return nil }
            }
        }
        return data
    }

    /// 流式计算整个文件的 SHA-256；读取中断返回 nil。
    /// 注意：read(upToCount:) 在到达文件末尾时返回 nil，按正常结束处理。
    private static func fullDigest(entry: FileEntry, hashedBytes: inout UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: entry.url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        hashedBytes += entry.size
        while true {
            guard let chunk = try? handle.read(upToCount: chunkLength), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
