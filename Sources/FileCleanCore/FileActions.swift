import Foundation
import AppKit

/// 删除保护规则：系统位置、运行中的本产品、以及不属于扫描结果的位置一律拒绝。
public enum FileProtector {

    /// 受保护的绝对路径前缀。任何普通清理都不应触碰这些位置。
    public static let protectedPrefixes: [String] = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple",
        "/Library/System", "/Applications/Xcode.app/Contents/Developer",
    ]

    /// 用户主目录内同样不做普通清理的关键目录。
    public static let protectedHomePrefixes: [String] = [
        "Library/Keychains", "Library/Mobile Documents", "Library/Mail",
        "Library/Messages", "Library/Accounts", "Library/IdentityServices",
    ]

    public static func isProtected(_ url: URL, home: String = NSHomeDirectory()) -> Bool {
        let path = url.standardizedFileURL.path
        // 根目录本身与一级系统位置。
        let components = path.split(separator: "/")
        if components.count <= 1 { return true }
        if protectedPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count + 1))
            if protectedHomePrefixes.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) { return true }
        }
        // 运行中的本产品自身。
        let bundle = Bundle.main.bundleURL.standardizedFileURL.path
        if path == bundle || path.hasPrefix(bundle + "/") { return true }
        return false
    }
}

/// 执行删除。每个文件在动作前重新核对身份（存在、inode、大小、修改时间），
/// 与扫描快照不一致时跳过并说明，绝不按过期快照删除。
public enum FileDeleter {

    public static func delete(_ entries: [FileEntry], mode: DeletionMode = .trash,
                              home: String = NSHomeDirectory()) -> [DeletionOutcome] {
        entries.map { entry in
            guard !FileProtector.isProtected(entry.url, home: home) else {
                return DeletionOutcome(url: entry.url, ending: .skippedProtected)
            }
            // 扫描用过的 URL 会缓存 resourceValues；重新构造并清缓存，避免拿旧元数据核对自身。
            var freshURL = URL(fileURLWithPath: entry.path)
            freshURL.removeAllCachedResourceValues()
            guard let current = try? freshURL.resourceValues(forKeys: [
                .fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]), current.isRegularFile == true, current.isSymbolicLink != true, !entry.isSymbolicLink else {
                return DeletionOutcome(url: entry.url, ending: .skippedChanged)
            }
            // 身份核对：inode、大小与修改时间必须与扫描时一致。
            if let inode = entry.inode, DiskScanner.inodeNumber(current.fileResourceIdentifier) != inode {
                return DeletionOutcome(url: entry.url, ending: .skippedChanged)
            }
            if UInt64(max(current.fileSize ?? 0, 0)) != entry.size {
                return DeletionOutcome(url: entry.url, ending: .skippedChanged)
            }
            if let scanned = entry.modifiedAt, let now = current.contentModificationDate,
               abs(now.timeIntervalSince(scanned)) > 0.001 {
                return DeletionOutcome(url: entry.url, ending: .skippedChanged)
            }

            return performAction(entry.url, mode: mode)
        }
    }

    /// 所有入口共用系统废纸篓语义；失败就返回错误，绝不降级为直接删除。
    /// 同步系统 API 避免 recycle 回调超时后仍在后台移动文件。
    static func performAction(_ url: URL, mode: DeletionMode = .trash,
                              trash: (URL) throws -> Void = moveToTrash) -> DeletionOutcome {
        do {
            switch mode {
            case .trash: try trash(url)
            case .permanent: try FileManager.default.removeItem(at: url)
            }
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return DeletionOutcome(url: url, ending: .failed("项目仍在原位置，未完成处理。"))
            }
            return DeletionOutcome(url: url, ending: mode == .trash ? .movedToTrash : .deleted)
        } catch {
            let message = mode == .trash
                ? "无法移入废纸篓，未执行永久删除：\(error.localizedDescription)"
                : error.localizedDescription
            return DeletionOutcome(url: url, ending: .failed(message))
        }
    }

    private static func moveToTrash(_ url: URL) throws {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
    }
}
