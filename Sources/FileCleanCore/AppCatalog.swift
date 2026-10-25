import Foundation

/// 已安装应用的只读清单：解析 .app 包的 bundle 元数据。
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let bundleURL: URL
    public let bundleID: String
    public let name: String
    public let version: String
    public let build: String
    public let isSystem: Bool
    public let isFromAppStore: Bool
    public let sparkleFeedURL: String?

    public var id: String { bundleURL.path }
    public var isUninstallable: Bool {
        // 系统卷应用与 Apple 自家应用受 SIP 或签名保护，一律不允许卸载。
        !isSystem && !bundleID.hasPrefix("com.apple.")
    }
}

public enum AppCatalog {

    /// 扫描常见安装位置；系统应用单独标记（仅展示，不可卸载）。
    public static func installedApps() -> [InstalledApp] {
        let locations = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Setapp", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        ]
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for location in locations {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: location, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for entry in entries where entry.pathExtension.lowercased() == "app" {
                let path = entry.path
                guard !seen.contains(path), let app = parse(bundleURL: entry) else { continue }
                seen.insert(path)
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 解析单个 .app 包；读取失败（权限、非包结构）返回 nil。
    public static func parse(bundleURL: URL, isSystem: Bool? = nil) -> InstalledApp? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else { return nil }
        let system = isSystem ?? bundleURL.path.hasPrefix("/System/")
        let receipt = bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt")
        return InstalledApp(
            bundleURL: bundleURL,
            bundleID: bundleID,
            name: (plist["CFBundleDisplayName"] as? String)
                ?? (plist["CFBundleName"] as? String)
                ?? bundleURL.deletingPathExtension().lastPathComponent,
            version: (plist["CFBundleShortVersionString"] as? String) ?? "0",
            build: (plist["CFBundleVersion"] as? String) ?? "0",
            isSystem: system,
            isFromAppStore: FileManager.default.fileExists(atPath: receipt.path),
            sparkleFeedURL: plist["SUFeedURL"] as? String,
        )
    }
}

/// 残留文件：属于（或疑似属于）某个应用的辅助位置。
public struct ResidualItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case preferences = "偏好设置"
        case caches = "缓存"
        case support = "应用数据"
        case containers = "容器"
        case groupContainers = "共享容器"
        case logs = "日志"
        case savedState = "窗口状态"
        case launchAgent = "启动项"
        case helpers = "辅助工具"
        case other = "其他"
    }

    public let url: URL
    public let kind: Kind
    public let sizeBytes: UInt64
    /// 匹配依据：命中的标识符；空串表示精确归属（如容器元数据）。
    public let matchedIdentifier: String

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var path: String { url.path }
}

/// 应用残留搜索：基于标识符缓存的快速归属思路。
/// 预计算归一化标识符集合，再去固定 Library 位置逐一匹配；
/// 严格档要求名称精确命中，增强档放宽为包含匹配。
public enum ResidualFinder {

    public enum Sensitivity: String, CaseIterable, Sendable {
        case strict = "精确"
        case enhanced = "增强"

        var allowContains: Bool { self == .enhanced }
    }

    /// helper/agent 类后缀：剥掉后用于匹配 LaunchAgents 里的辅助进程 plist。
    static let helperSuffixes = ["helper", "agent", "daemon", "service", "xpc", "launcher", "updater",
                                 "installer", "uninstaller", "login", "extension", "plugin"]

    /// 归一化：小写、去点、仅保留字母数字。
    public static func normalize(_ raw: String) -> String {
        String(raw.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 为应用生成标识符缓存（全部归一化，长度 ≥ 4 才可信）。
    public static func identifiers(for app: InstalledApp) -> [String] {
        var result = Set<String>()
        let insert = { (value: String) in
            let normalized = normalize(value)
            if normalized.count >= 4 { result.insert(normalized) }
        }
        insert(app.bundleID)
        // com.knollsoft.Rectangle → knollsoftrectangle
        let parts = app.bundleID.split(separator: ".").map(String.init)
        if parts.count >= 2 { insert(parts.suffix(2).joined()) }
        // 应用名：原样、去尾部数字（Firefox 120.0 → Firefox）
        insert(app.name)
        insert(app.name.replacingOccurrences(of: "\\d+(\\.\\d+)*\\s*$", with: "", options: .regularExpression))
        // base bundle id：剥 helper 后缀（com.acme.tool.helper → com.acme.tool）
        if parts.count >= 3 {
            let last = parts.last?.lowercased() ?? ""
            if helperSuffixes.contains(last) {
                insert(parts.dropLast().joined(separator: "."))
            }
        }
        return Array(result)
    }

    /// 残留搜索的固定位置（用户级 + 可读的系统级）。
    static var searchLocations: [(URL, ResidualItem.Kind)] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
        return [
            (library.appendingPathComponent("Preferences"), .preferences),
            (library.appendingPathComponent("Caches"), .caches),
            (library.appendingPathComponent("Application Support"), .support),
            (library.appendingPathComponent("Logs"), .logs),
            (library.appendingPathComponent("Saved Application State"), .savedState),
            (library.appendingPathComponent("HTTPStorages"), .other),
            (library.appendingPathComponent("WebKit"), .other),
            (library.appendingPathComponent("Application Scripts"), .other),
            (library.appendingPathComponent("LaunchAgents"), .launchAgent),
            (systemLibrary.appendingPathComponent("Application Support"), .support),
            (systemLibrary.appendingPathComponent("Caches"), .caches),
            (systemLibrary.appendingPathComponent("Logs"), .logs),
            (systemLibrary.appendingPathComponent("LaunchAgents"), .launchAgent),
            (systemLibrary.appendingPathComponent("LaunchDaemons"), .launchAgent),
            (systemLibrary.appendingPathComponent("PrivilegedHelperTools"), .helpers),
        ]
    }

    /// 搜索某个应用的残留；appBundleURL 自身与系统位置自动排除。
    public static func findResiduals(for app: InstalledApp, sensitivity: Sensitivity) -> [ResidualItem] {
        let identifiers = identifiers(for: app)
        var results: [ResidualItem] = []
        for (location, kind) in searchLocations {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: location, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
            for entry in entries {
                if entry.path.hasPrefix("/System/") || entry.path.hasPrefix("/Library/Apple") { continue }
                if match(entry: entry, identifiers: identifiers, sensitivity: sensitivity) {
                    results.append(ResidualItem(
                        url: entry, kind: kind,
                        sizeBytes: itemSize(entry),
                        matchedIdentifier: normalize(entry.deletingPathExtension().lastPathComponent)))
                }
            }
        }
        results += containers(for: app)
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Containers / Group Containers 通过元数据 plist 反查归属（精确，不靠名称猜）。
    static func containers(for app: InstalledApp) -> [ResidualItem] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        var results: [ResidualItem] = []
        for (directory, kind) in [(library.appendingPathComponent("Containers"), ResidualItem.Kind.containers),
                                  (library.appendingPathComponent("Group Containers"), .groupContainers)] {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let metadata = entry.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
                guard let data = try? Data(contentsOf: metadata),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let owner = plist["MCMMetadataIdentifier"] as? String else { continue }
                if owner == app.bundleID {
                    results.append(ResidualItem(url: entry, kind: kind, sizeBytes: itemSize(entry), matchedIdentifier: "container"))
                }
            }
        }
        return results
    }

    /// 名称匹配：剥扩展名（.plist 等）后与标识符比较。
    static func match(entry: URL, identifiers: [String], sensitivity: Sensitivity) -> Bool {
        let stem = normalize(entry.deletingPathExtension().lastPathComponent)
        guard !stem.isEmpty else { return false }
        for identifier in identifiers {
            if stem == identifier { return true }
            if sensitivity.allowContains && stem.contains(identifier) { return true }
        }
        return false
    }

    /// 目录聚合逻辑大小；单个文件直接取大小。读取失败计 0。
    public static func itemSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isRegularFileKey])
        if values?.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []) else { return 0 }
            var total: UInt64 = 0
            for case let child as URL in enumerator {
                if let childValues = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                   childValues.isRegularFile == true, childValues.isSymbolicLink != true {
                    total += UInt64(max(childValues.fileSize ?? 0, 0))
                }
            }
            return total
        }
        return UInt64(max(values?.fileSize ?? 0, 0))
    }
}
