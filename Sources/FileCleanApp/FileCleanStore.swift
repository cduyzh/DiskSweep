import SwiftUI
import AppKit
import FileCleanCore
import Combine

@MainActor
final class FileCleanStore: ObservableObject {

    enum Page: String, CaseIterable, Identifiable {
        case overview, treemap, tree, large, duplicates, uninstall, junk, updates, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "磁盘概览"
            case .treemap: return "空间视图"
            case .tree: return "目录整理"
            case .large: return "大文件"
            case .duplicates: return "重复文件"
            case .uninstall: return "应用卸载"
            case .junk: return "垃圾清理"
            case .updates: return "软件更新"
            case .settings: return "设置"
            }
        }
        var symbol: String {
            switch self {
            case .overview: return "internaldrive"
            case .treemap: return "square.grid.3x3"
            case .tree: return "folder"
            case .large: return "doc.richtext.fill"
            case .duplicates: return "square.on.square"
            case .uninstall: return "app.dashed"
            case .junk: return "xmark.bin"
            case .updates: return "arrow.triangle.2.circlepath"
            case .settings: return "slider.horizontal.3"
            }
        }
        var section: String {
            switch self {
            case .overview, .treemap, .tree, .large, .duplicates: return "磁盘"
            case .uninstall, .junk, .updates: return "应用"
            case .settings: return "设置"
            }
        }
    }

    struct PendingUninstall: Equatable {
        let app: InstalledApp
        let residuals: [ResidualItem]
        let mode: DeletionMode
    }

    enum DuplicatesStage: Equatable {
        case idle, running, done(Date), failed(String)
    }

    // MARK: 导航与面板

    @Published var page: Page = .overview
    @Published var showInspector = true

    // MARK: 扫描状态

    @Published var scanStage: ScanStage = .idle
    @Published var progress = ScanProgress()
    @Published var result: ScanResult? { didSet {
        removedFilePaths.removeAll()
        refreshLargeFiles()
    } }
    @Published var resultStale = false
    @Published var volumes: [VolumeInfo] = []
    @Published var duplicatesStage: DuplicatesStage = .idle
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var duplicateStats: (sampled: UInt64, hashed: UInt64, cached: UInt64) = (0, 0, 0)

    // MARK: 选择与反馈

    @Published var selectedEntry: FileEntry?
    @Published var error: String?
    @Published var notice: String?
    @Published var showReleaseHistory = false

    // MARK: 删除确认

    @Published var pendingDeletion: [FileEntry] = []
    @Published var pendingMode: DeletionMode = .trash

    /// 垃圾清理 / 残留删除的 URL 级确认流（目录目标不做文件身份核对，按存在性核对）。
    @Published var pendingURLDeletion: [URL] = []
    @Published var pendingURLMode: DeletionMode = .trash
    @Published var pendingURLBytes: UInt64 = 0
    @Published var pendingUninstall: PendingUninstall?
    @Published private(set) var processingDeletion = false

    // MARK: 大文件分类（只读视图，不移动文件）

    @Published private(set) var largeFiles: [FileEntry] = []
    @Published private(set) var largeFileCategories: [FileCategorySummary] = []
    @Published var largeFileCategory: FileCategory?
    @Published var largeFileQuery = ""
    @Published var largeFileSort: LargeFileSort = .size
    var filteredLargeFiles: [FileEntry] {
        largeFileSort.filter(largeFiles, category: largeFileCategory, query: largeFileQuery)
    }

    // MARK: 应用与垃圾清理（v0.2）

    @Published var apps: [InstalledApp] = []
    @Published var appsLoading = false
    @Published var selectedApp: InstalledApp?
    @Published var residuals: [ResidualItem] = []
    @Published var residualScanning = false
    @Published var residualSensitivity: Int { didSet { defaults.set(residualSensitivity, forKey: "residualSensitivity") } }
    @Published var residualSelected = Set<String>()

    @Published var orphans: [OrphanItem] = []
    @Published var orphansScanning = false
    @Published var orphanSelected = Set<String>()

    @Published var updateStatuses: [String: UpdateStatus] = [:]
    @Published var updatesChecking = false

    @Published var snapshots: [LocalSnapshot] = []
    @Published var snapshotError: String?
    @Published var purgeableBytes: UInt64?

    /// treemap 面包屑：从根到当前层的节点路径栈。
    @Published var treemapPathStack: [String] = []

    // MARK: 偏好（UserDefaults 持久化）

    @Published var appearance: Int { didSet { defaults.set(appearance, forKey: "appearance") } }
    @Published var skipHidden: Bool { didSet { defaults.set(skipHidden, forKey: "skipHidden") } }
    @Published var minDuplicateMiB: Int { didSet { defaults.set(minDuplicateMiB, forKey: "minDuplicateMiB") } }
    @Published var largeFileMiB: Int { didSet {
        defaults.set(largeFileMiB, forKey: "largeFileMiB")
        refreshLargeFiles()
    } }

    var colorScheme: ColorScheme? {
        switch appearance {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private let defaults = UserDefaults.standard
    private var scanner: DiskScanner?
    private var removedFilePaths = Set<String>()

    var scanning: Bool { scanStage.isRunning }
    var scanRootURL: URL {
        result?.rootURL ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    init() {
        appearance = defaults.object(forKey: "appearance") as? Int ?? 0
        skipHidden = defaults.object(forKey: "skipHidden") as? Bool ?? false
        minDuplicateMiB = defaults.object(forKey: "minDuplicateMiB") as? Int ?? 1
        largeFileMiB = defaults.object(forKey: "largeFileMiB") as? Int ?? 100
        residualSensitivity = defaults.object(forKey: "residualSensitivity") as? Int ?? 0
    }

    var sensitivity: ResidualFinder.Sensitivity {
        residualSensitivity == 1 ? .enhanced : .strict
    }

    // MARK: 卷信息

    func refreshVolumes() {
        volumes = DiskScanner.mountedVolumes()
    }

    // MARK: 扫描

    private func refreshLargeFiles() {
        largeFiles = (result?.largeFiles(threshold: UInt64(largeFileMiB) << 20) ?? [])
            .filter { !removedFilePaths.contains($0.id) }
        largeFileCategories = FileCategorySummary.summarize(largeFiles)
    }

    func chooseScanDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "扫描此文件夹"
        panel.message = "选择要分析的文件夹；扫描只读取文件信息。"
        if panel.runModal() == .OK, let url = panel.url { startScan(root: url) }
    }

    func startScan(root: URL? = nil) {
        guard !scanning, !processingDeletion else { return }
        error = nil
        notice = nil
        resultStale = false
        duplicateGroups = []
        selectedEntry = nil
        largeFileCategory = nil
        largeFileQuery = ""
        duplicatesStage = .idle
        let options = ScanOptions(
            scanRoot: root ?? URL(fileURLWithPath: NSHomeDirectory()),
            minDuplicateSize: UInt64(minDuplicateMiB) << 20,
            largeFileThreshold: UInt64(largeFileMiB) << 20,
            skipHidden: skipHidden,
            treeChildLimit: 12,
            excludedPaths: ScanOptions.defaultExclusions)
        let scanner = DiskScanner(options: options) { [weak self] snapshot in
            Task { @MainActor in
                self?.progress = snapshot
                self?.scanStage = snapshot.stage
            }
        }
        self.scanner = scanner
        scanStage = .enumerating
        progress = ScanProgress(stage: .enumerating, currentPath: options.scanRoot.path)
        Task {
            do {
                let outcome = try await Background.run { try scanner.start() }
                self.result = outcome
                self.scanStage = .finishedAt(outcome.finishedAt)
                self.progress.currentPath = ""
                self.refreshVolumes()
                self.notice = "扫描完成：\(Format.count(outcome.totalFiles)) 个文件 · \(Format.bytes(outcome.totalLogicalBytes))"
            } catch {
                self.scanStage = .failed(error.localizedDescription)
                self.error = "扫描失败：\(error.localizedDescription)"
            }
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    // MARK: 重复检测

    func runDuplicateScan() {
        guard let result, !duplicatesStage.isRunningLike else { return }
        duplicatesStage = .running
        let candidates = result.candidates
        let minSize = UInt64(minDuplicateMiB) << 20
        let cache = try? HashCache()
        Task {
            do {
                let outcome = try await Background.run {
                    DuplicateFinder.findGroups(in: candidates, minSize: minSize, cache: cache)
                }
                self.duplicateGroups = outcome.groups
                self.duplicateStats = (outcome.sampledBytes, outcome.hashedBytes, outcome.cachedBytes)
                self.duplicatesStage = .done(Date())
                if let cache {
                    // 修剪缓存：只保留本次扫描确认仍然有效的键。
                    let keys = candidates.map {
                        (path: $0.path, size: $0.size, mtimeNs: HashCache.mtimeNanoseconds($0.modifiedAt))
                    }
                    _ = try? await Background.run { cache.prune(validKeys: keys) }
                }
            } catch {
                self.duplicatesStage = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: 删除

    func requestDeletion(_ entries: [FileEntry], mode: DeletionMode = .trash) {
        guard !entries.isEmpty, !processingDeletion, !scanning else { return }
        pendingDeletion = entries
        pendingMode = mode
    }

    func performPendingDeletion() {
        let entries = pendingDeletion
        let mode = pendingMode
        pendingDeletion = []
        guard !entries.isEmpty else { return }
        processingDeletion = true
        Task {
            defer { self.processingDeletion = false }
            let outcomes = (try? await Background.run {
                FileDeleter.delete(entries, mode: mode)
            }) ?? []
            let moved = outcomes.filter(\.succeeded)
            let reclaimed = moved.reduce(UInt64(0)) { sum, outcome in
                sum + (entries.first { $0.path == outcome.url.path }?.size ?? 0)
            }
            let skipped = outcomes.filter { !$0.succeeded }
            if moved.isEmpty {
                self.error = "没有文件被\(mode == .trash ? "移入废纸篓" : "删除")" + (skipped.isEmpty ? "" : "：\(skipped.count) 个被跳过或失败")
            } else {
                self.notice = "\(mode == .trash ? "已移入废纸篓" : "已删除") \(Format.count(moved.count)) 个文件 · \(Format.bytes(reclaimed))"
                if !skipped.isEmpty {
                    self.notice? += "；\(Format.count(skipped.count)) 个被跳过或失败"
                }
                self.resultStale = true
                let removed = Set(moved.map { $0.url.path })
                self.removedFilePaths.formUnion(removed)
                self.largeFiles.removeAll { removed.contains($0.id) }
                self.largeFileCategories = FileCategorySummary.summarize(self.largeFiles)
                if let selected = self.selectedEntry, removed.contains(selected.id) { self.selectedEntry = nil }
                self.duplicateGroups = self.duplicateGroups.compactMap { group in
                    let remaining = group.files.filter { !removed.contains($0.id) }
                    guard remaining.count > 1 else { return nil }
                    return DuplicateGroup(contentDigest: group.contentDigest, fileSize: group.fileSize, files: remaining)
                }
            }
            for outcome in outcomes where outcome.ending != .movedToTrash && outcome.ending != .deleted {
                if case .failed(let message) = outcome.ending {
                    self.error = "\(outcome.url.lastPathComponent)：\(message)"
                }
            }
        }
    }

    func totalReclaimableBytes(_ groups: [DuplicateGroup]) -> UInt64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    // MARK: 访达与复制

    func revealInFinder(_ entry: FileEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    func copyPath(_ entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path, forType: .string)
        notice = "已复制路径：\(entry.path)"
    }

    // MARK: 导出

    /// 导出当前页面清单为 CSV（UTF-8 BOM，防护电子表格公式注入）。
    func exportCSV() {
        let lines: [[String]]
        let suggestedName: String
        switch page {
        case .large:
            lines = [["路径", "名称", "文件种类", "字节数", "修改时间"]]
                + filteredLargeFiles.map { [$0.path, $0.name, $0.category.title, String($0.size), Format.date($0.modifiedAt)] }
            suggestedName = "大文件清单.csv"
        case .duplicates:
            lines = [["分组摘要", "路径", "字节数"]]
                + duplicateGroups.flatMap { group in
                    group.files.map { [group.contentDigest.prefix(12).description, $0.path, String($0.size)] }
                }
            suggestedName = "重复文件清单.csv"
        default:
            error = "当前页面没有可导出的清单；大文件与重复文件页面支持导出 CSV。"
            return
        }
        let csv = Self.csv(lines)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                notice = "已导出：\(url.path)"
            } catch {
                self.error = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    static func csv(_ rows: [[String]]) -> String {
        let guarded = rows.map { row in
            row.map { cell in
                let quoted = "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
                if cell.hasPrefix("=") || cell.hasPrefix("+") || cell.hasPrefix("-") || cell.hasPrefix("@") {
                    return "'" + quoted
                }
                return quoted
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
        return "\u{FEFF}" + guarded + "\r\n"
    }

    // MARK: 导航

    func navigate(_ target: Page) {
        page = target
        if target == .uninstall, apps.isEmpty, !appsLoading { loadApps() }
    }

    // MARK: 应用清单与残留（v0.2）

    func loadApps() {
        guard !appsLoading else { return }
        appsLoading = true
        Task {
            let loaded = (try? await Background.run { AppCatalog.installedApps() }) ?? []
            self.apps = loaded
            self.appsLoading = false
            if let current = selectedApp {
                self.selectedApp = loaded.first { $0.id == current.id } ?? loaded.first
            }
        }
    }

    func selectApp(_ app: InstalledApp?) {
        selectedApp = app
        residuals = []
        residualSelected = []
        if let app {
            findResiduals(for: app)
        }
    }

    func findResiduals(for app: InstalledApp) {
        guard !residualScanning else { return }
        residualScanning = true
        let sensitivity = self.sensitivity
        Task {
            let found = (try? await Background.run {
                ResidualFinder.findResiduals(for: app, sensitivity: sensitivity)
            }) ?? []
            self.residuals = found
            // 默认只勾选缓存与日志类残留；应用数据（支持文件）交给用户自行判断。
            self.residualSelected = Set(found.filter { $0.kind == .caches || $0.kind == .logs }.map(\.id))
            self.residualScanning = false
        }
    }

    var selectedResiduals: [ResidualItem] {
        residuals.filter { residualSelected.contains($0.id) }
    }

    var residualTotalBytes: UInt64 {
        residuals.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: 垃圾清理（v0.2）

    func runOrphanScan() {
        guard !orphansScanning else { return }
        orphansScanning = true
        orphans = []
        orphanSelected = []
        Task {
            let found = (try? await Background.run {
                OrphanFinder.findOrphans(installedApps: AppCatalog.installedApps())
            }) ?? []
            self.orphans = found
            self.orphansScanning = false
        }
    }

    var selectedOrphans: [OrphanItem] {
        orphans.filter { orphanSelected.contains($0.id) }
    }

    func requestOrphanDeletion(_ items: [OrphanItem], mode: DeletionMode = .trash) {
        guard !items.isEmpty, !processingDeletion else { return }
        pendingURLDeletion = items.map(\.url)
        pendingURLMode = mode
        pendingURLBytes = items.reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: 软件更新（v0.2）

    var uninstallableApps: [InstalledApp] {
        apps.filter(\.isUninstallable)
    }

    func checkUpdates() {
        guard !updatesChecking else { return }
        updatesChecking = true
        updateStatuses = [:]
        let targets = uninstallableApps
        Task {
            try? await withThrowingTaskGroup(of: (String, UpdateStatus).self) { group in
                var iterator = targets.makeIterator()
                var inFlight = 0
                func addNext() {
                    guard let app = iterator.next() else { return }
                    inFlight += 1
                    group.addTask { (app.id, await UpdateChecker.check(app: app)) }
                }
                for _ in 0..<4 { addNext() }
                while let next = try await group.next() {
                    self.updateStatuses[next.0] = next.1
                    inFlight -= 1
                    addNext()
                }
                _ = inFlight
            }
            self.updatesChecking = false
        }
    }

    var availableUpdates: [UpdateStatus] {
        updateStatuses.values.filter {
            if case .updateAvailable = $0.state { return true }
            return false
        }
    }

    // MARK: 快照（v0.2）

    func refreshSnapshots() {
        let outcome = SnapshotInspector.localSnapshots()
        snapshots = outcome.snapshots
        snapshotError = outcome.error
        purgeableBytes = SnapshotInspector.purgeableEstimate(volumeURL: URL(fileURLWithPath: "/"))
    }

    // MARK: URL 级删除执行（垃圾 / 残留 / 卸载）

    func performPendingURLDeletion() {
        let urls = pendingURLDeletion
        let mode = pendingURLMode
        pendingURLDeletion = []
        guard !urls.isEmpty else { return }
        processingDeletion = true
        Task {
            defer { self.processingDeletion = false }
            let outcomes = (try? await Background.run {
                FileDeleter.deletePaths(urls, mode: mode)
            }) ?? []
            let moved = outcomes.filter(\.succeeded)
            let failed = outcomes.filter { !$0.succeeded }
            if moved.isEmpty {
                self.error = "没有项目被\(mode == .trash ? "移入废纸篓" : "删除")"
            } else {
                self.notice = "\(mode == .trash ? "已移入废纸篓" : "已删除") \(Format.count(moved.count)) 项"
                if urls.contains(where: { $0.pathExtension == "app" }) {
                    // 卸载或删除应用后清单可能变化，重新加载。
                    self.loadApps()
                }
                if mode == .trash {
                    // 垃圾清理移除后刷新孤儿列表。
                    self.runOrphanScan()
                }
                self.resultStale = true
            }
            if !failed.isEmpty {
                self.error = "\(failed.count) 项未处理。" + failed.compactMap {
                    if case .failed(let message) = $0.ending { return "\($0.url.lastPathComponent)：\(message)" }
                    return "\($0.url.lastPathComponent)：受保护或已变化"
                }.prefix(3).joined(separator: "；")
            }
        }
    }

    func performPendingUninstall() {
        guard let pending = pendingUninstall else { return }
        pendingUninstall = nil
        processingDeletion = true
        Task {
            defer { self.processingDeletion = false }
            let outcome = (try? await Background.run {
                AppUninstaller.uninstall(app: pending.app, residuals: pending.residuals, mode: pending.mode)
            })
            guard let outcome else {
                self.error = "卸载执行失败"
                return
            }
            if outcome.succeeded {
                let count = outcome.residualResults.filter(\.succeeded).count
                self.notice = "已卸载 \(pending.app.name)" + (count > 0 ? "，并清理 \(Format.count(count)) 项残留" : "")
                let failedCount = outcome.residualResults.filter { !$0.succeeded }.count
                if failedCount > 0 { self.error = "应用已移入废纸篓；\(failedCount) 项残留未能处理，请在访达中查看。" }
                self.selectedApp = nil
                self.residuals = []
                self.residualSelected = []
                self.loadApps()
                self.resultStale = true
            } else if case .skippedProtected = outcome.appBundleResult.ending {
                self.error = AppUninstaller.uninstallBlockedReason(for: pending.app) ?? "该应用受保护，不能卸载。"
            } else if case .failed(let message) = outcome.appBundleResult.ending {
                self.error = "卸载失败：\(message)"
            } else {
                self.error = "卸载未执行：应用包已不在预期位置。"
            }
        }
    }
}

extension FileCleanStore.DuplicatesStage {
    var isRunningLike: Bool {
        if case .running = self { return true }
        return false
    }
}
