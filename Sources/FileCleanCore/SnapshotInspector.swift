import Foundation

/// APFS 本地快照与可清除空间的只读检查。
/// 删除本地快照需要管理员权限，本工具不提权、不执行删除；
/// 只列出真实快照、估算可清除量并给出系统入口指引。
public struct LocalSnapshot: Identifiable, Hashable, Sendable {
    public let rawName: String
    public let volume: String

    public var id: String { "\(volume):\(rawName)" }
    /// com.apple.TimeMachine.2026-10-24-101112.backup → 2026-10-24 10:11:12（尽力解析）。
    public var displayDate: String {
        // 名称固定为 com.apple.TimeMachine.<时间戳>.backup 五段。
        let segments = rawName.split(separator: ".")
        guard segments.count >= 5 else { return rawName }
        let stamp = String(segments[3])
        let parts = stamp.split(separator: "-")
        guard parts.count == 4, parts[3].count == 6 else { return rawName }
        let time = parts[3]
        let start = time.startIndex
        let hh = String(time[start...time.index(start, offsetBy: 1)])
        let mm = String(time[time.index(start, offsetBy: 2)...time.index(start, offsetBy: 3)])
        let ss = String(time[time.index(start, offsetBy: 4)...time.index(start, offsetBy: 5)])
        return "\(parts[0])-\(parts[1])-\(parts[2]) \(hh):\(mm):\(ss)"
    }
}

public enum SnapshotInspector {

    /// 运行 tmutil listlocalsnapshots 解析本卷快照；命令缺失或失败返回空并说明。
    public static func localSnapshots(volumePath: String = "/") -> (snapshots: [LocalSnapshot], error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", volumePath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ([], "无法运行 tmutil：\(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return ([], "tmutil 返回错误（状态 \(process.terminationStatus)）")
        }
        let output = String(data: data, encoding: .utf8) ?? ""
        let names = output.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 输出行形如：com.apple.TimeMachine.2026-10-24-101112.backup
            guard trimmed.hasPrefix("com.apple.TimeMachine."), trimmed.hasSuffix(".backup") else { return nil }
            return trimmed
        }
        return (names.map { LocalSnapshot(rawName: $0, volume: volumePath) }, nil)
    }

    /// 可清除空间估算：重要用途可用 - 紧急用途可用 ≥ 0 的部分近似为 purgeable。
    /// 口径与磁盘工具可能不同；只作提示，不当成精确值。
    public static func purgeableEstimate(volumeURL: URL) -> UInt64? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys),
              let important = values.volumeAvailableCapacityForImportantUsage,
              let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage else { return nil }
        let difference = important - opportunistic
        return difference > 0 ? UInt64(difference) : 0
    }
}
