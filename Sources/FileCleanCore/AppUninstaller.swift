import Foundation
import AppKit

/// 卸载动作：应用包 + 选定残留一起处理。
/// 系统应用、运行中的应用受保护；全部走废纸篓/永久删除的既有安全通道。
public enum AppUninstaller {

    public struct Outcome: Sendable {
        public let appBundleResult: DeletionOutcome
        public let residualResults: [DeletionOutcome]
        public var succeeded: Bool { appBundleResult.succeeded }
    }

    /// 卸载前检查：返回不可卸载的原因（可卸载返回 nil）。
    public static func uninstallBlockedReason(for app: InstalledApp) -> String? {
        guard app.isUninstallable else {
            return app.isSystem ? "系统应用受 macOS 保护，不能卸载。" : "Apple 应用不允许卸载。"
        }
        // 运行中的应用先退出再卸载；通过 bundle URL 精确匹配，不按名称猜。
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        if !running.isEmpty {
            return "应用正在运行（\(running.count) 个进程），请先退出。"
        }
        if !FileManager.default.isWritableFile(atPath: app.bundleURL.deletingLastPathComponent().path) {
            return "安装位置需要管理员权限，本工具不提权；请手动处理。"
        }
        return nil
    }

    /// 执行卸载：应用包本体 + 用户勾选的残留路径。
    public static func uninstall(app: InstalledApp, residuals: [ResidualItem], mode: DeletionMode = .trash) -> Outcome {
        guard uninstallBlockedReason(for: app) == nil else {
            return Outcome(
                appBundleResult: DeletionOutcome(url: app.bundleURL, ending: .skippedProtected),
                residualResults: [])
        }
        let appResult = FileDeleter.deleteBundles([app.bundleURL], mode: mode).first
            ?? DeletionOutcome(url: app.bundleURL, ending: .failed("未知错误"))
        // 应用本体处理失败时保留其残留，避免破坏仍在原位的应用数据。
        let residualResults = appResult.succeeded ? FileDeleter.deletePaths(residuals.map(\.url), mode: mode) : []
        return Outcome(appBundleResult: appResult, residualResults: residualResults)
    }
}

public extension FileDeleter {
    /// 删除目录类目标（应用包、残留目录）：不要求 isRegularFile，仅核对存在与保护名单。
    static func deleteBundles(_ urls: [URL], mode: DeletionMode = .trash) -> [DeletionOutcome] {
        urls.map { url in
            guard !FileProtector.isProtected(url) else {
                return DeletionOutcome(url: url, ending: .skippedProtected)
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return DeletionOutcome(url: url, ending: .skippedChanged)
            }
            return performAction(url, mode: mode)
        }
    }

    /// 残留路径删除：保护名单 + 存在性核对（目录不做 mtime 核对，条目以路径为准）。
    static func deletePaths(_ urls: [URL], mode: DeletionMode = .trash) -> [DeletionOutcome] {
        deleteBundles(urls, mode: mode)
    }
}
