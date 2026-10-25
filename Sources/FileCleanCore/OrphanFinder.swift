import Foundation

/// 孤儿垃圾检测（反向路径搜索思路）：
/// 枚举 Library 常驻位置的顶层条目，反查是否归属任何已安装应用；
/// 无归属且不属于系统保护的条目列为可清理候选。
public struct OrphanItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let kind: ResidualItem.Kind
    public let sizeBytes: UInt64
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var path: String { url.path }
}

public enum OrphanFinder {

    /// 已知系统/框架前缀：这些条目即使无应用归属也不属于垃圾。
    static let protectedPrefixes = ["com.apple", "Apple", "apple", "com.crashlytics", "macromedia"]

    /// 检测孤儿条目。installedApps 提供归属反查的标识符全集。
    /// 返回结果按体积降序；只读，不修改任何文件。
    public static func findOrphans(installedApps: [InstalledApp]) -> [OrphanItem] {
        // 全量应用的归一化标识符缓存（一次构建，内存常驻）。
        var allIdentifiers = Set<String>()
        for app in installedApps {
            ResidualFinder.identifiers(for: app).forEach { allIdentifiers.insert($0) }
            allIdentifiers.insert(ResidualFinder.normalize(app.bundleID))
        }
        // 容器归属集合：元数据里登记的 bundle ID 全部视为"有主"。
        var containerOwners = Set<String>()
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        for directory in [library.appendingPathComponent("Containers"),
                          library.appendingPathComponent("Group Containers")] {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let metadata = entry.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
                if let data = try? Data(contentsOf: metadata),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let owner = plist["MCMMetadataIdentifier"] as? String {
                    containerOwners.insert(owner)
                    containerOwners.insert(ResidualFinder.normalize(owner))
                }
            }
        }

        var results: [OrphanItem] = []
        for (location, kind) in ResidualFinder.searchLocations {
            guard location.path.hasPrefix(NSHomeDirectory()) else { continue } // 孤儿清理只动用户目录
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: location, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries {
                let stem = ResidualFinder.normalize(entry.deletingPathExtension().lastPathComponent)
                guard !stem.isEmpty, stem.count >= 3 else { continue }
                if protectedPrefixes.contains(where: { stem.hasPrefix(ResidualFinder.normalize($0)) }) { continue }
                // LaunchAgents 的 .plist 属主可能在内容里；名称即可粗判。
                var owned = allIdentifiers.contains(stem)
                if !owned && kind == .containers {
                    owned = containerOwners.contains(stem)
                }
                if !owned {
                    results.append(OrphanItem(url: entry, kind: kind, sizeBytes: ResidualFinder.itemSize(entry)))
                }
            }
        }
        return results.filter { $0.sizeBytes > 0 || $0.kind == .launchAgent }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
