import SwiftUI
import AppKit
import FileCleanCore

struct WorkspaceView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                if let error = store.error { banner(error, symbol: "exclamationmark.circle", color: Palette.orange, isError: true) }
                if let notice = store.notice { banner(notice, symbol: "checkmark.circle", color: Palette.accent, isError: false) }
                if store.resultStale, store.page != .settings { staleBanner }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
        }
        .background(Palette.background)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $store.showReleaseHistory) { ReleaseHistoryView() }
        .alert(
            store.pendingMode == .trash ? "将这些文件移入废纸篓？" : "永久删除这些文件？",
            isPresented: Binding(get: { !store.pendingDeletion.isEmpty }, set: { if !$0 { store.pendingDeletion = [] } })
        ) {
            Button("取消", role: .cancel) { store.pendingDeletion = [] }
            Button(store.pendingMode == .trash ? "移入废纸篓" : "永久删除", role: .destructive) {
                store.performPendingDeletion()
            }
        } message: {
            let count = store.pendingDeletion.count
            let bytes = store.pendingDeletion.reduce(UInt64(0)) { $0 + $1.size }
            Text("\(Format.count(count)) 个文件 · \(Format.bytes(bytes))\n")
                + Text(store.pendingMode == .trash
                       ? "可从废纸篓恢复。删除前会逐一核对文件与扫描时一致。"
                       : "永久删除不可恢复。删除前会逐一核对文件与扫描时一致。")
        }
        .alert(
            store.pendingURLMode == .trash ? "将这些项目移入废纸篓？" : "永久删除这些项目？",
            isPresented: Binding(get: { !store.pendingURLDeletion.isEmpty }, set: { if !$0 { store.pendingURLDeletion = [] } })
        ) {
            Button("取消", role: .cancel) { store.pendingURLDeletion = [] }
            Button(store.pendingURLMode == .trash ? "移入废纸篓" : "永久删除", role: .destructive) {
                store.performPendingURLDeletion()
            }
        } message: {
            Text("\(Format.count(store.pendingURLDeletion.count)) 项 · 约 \(Format.bytes(store.pendingURLBytes))\n")
                + Text(store.pendingURLMode == .trash
                       ? "可从废纸篓恢复。删除前核对路径仍然存在。"
                       : "永久删除不可恢复。删除前核对路径仍然存在。")
        }
        .alert(
            store.pendingUninstall?.mode == .trash ? "卸载这个应用？" : "卸载并永久删除这个应用？",
            isPresented: Binding(get: { store.pendingUninstall != nil }, set: { if !$0 { store.pendingUninstall = nil } })
        ) {
            Button("取消", role: .cancel) { store.pendingUninstall = nil }
            Button(store.pendingUninstall?.mode == .trash ? "移入废纸篓并卸载" : "卸载并永久删除", role: .destructive) {
                store.performPendingUninstall()
            }
        } message: {
            if let pending = store.pendingUninstall {
                Text("\(pending.app.name) \(pending.app.version)\n应用包与 \(Format.count(pending.residuals.count)) 项勾选残留将一并处理。")
                    + Text(pending.mode == .trash ? "移入废纸篓，可恢复。" : "永久删除不可恢复。")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.page {
        case .overview:
            DiskOverviewView()
        case .treemap:
            TreemapView()
            footer
        case .tree:
            DirectoryTreeView()
            footer
        case .large:
            HStack(spacing: 0) {
                LargeFilesView()
                inspector
            }
            footer
        case .duplicates:
            HStack(spacing: 0) {
                DuplicatesView()
                inspector
            }
            footer
        case .uninstall:
            AppUninstallView()
            footer
        case .junk:
            JunkView()
            footer
        case .updates:
            UpdatesView()
            footer
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if store.showInspector {
            Rectangle().fill(Palette.line).frame(width: 1)
            InspectorView().frame(width: 248)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.page.section + "  /  FileClean")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text(store.page.title).font(.system(size: 27, weight: .semibold)).tracking(-0.7)
                Text(pageDescription).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if store.page != .settings {
                scanStatus
                HStack(spacing: 6) {
                    if store.scanning {
                        ToolButton(symbol: "stop.circle", label: "取消扫描") { store.cancelScan() }
                    } else {
                        Menu {
                            Button("扫描用户目录") { store.startScan() }
                            Button("选择文件夹…") { store.chooseScanDirectory() }
                            if store.result != nil {
                                Button("重新扫描当前文件夹") { store.startScan(root: store.scanRootURL) }
                            }
                        } label: {
                            Label("扫描文件夹", systemImage: "magnifyingglass")
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .foregroundStyle(Palette.accent)
                        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        .disabled(store.processingDeletion)
                    }
                    if store.page == .duplicates {
                        ToolButton(symbol: "dot.scope", label: "重复文件检测") { store.runDuplicateScan() }
                            .disabled(store.result == nil)
                    }
                    if store.page == .large || store.page == .duplicates {
                        ToolButton(symbol: "square.and.arrow.up", label: "导出清单 CSV ⌘S") { store.exportCSV() }
                        Divider().frame(height: 17).padding(.horizontal, 5)
                        ToolButton(symbol: "sidebar.right", label: "显示 / 隐藏详情 ⌥⌘I", selected: store.showInspector) { store.showInspector.toggle() }
                    }
                }
            }
        }
        .padding(.horizontal, 26).padding(.top, 38).padding(.bottom, 22)
    }

    private var pageDescription: String {
        switch store.page {
        case .overview: return "看清空间分布，让整理更有把握。"
        case .large: return "按种类找到空间大户，逐项确认后再整理。"
        case .duplicates: return "比对文件内容，留下一份需要的副本。"
        case .tree: return "从文件夹开始，逐层查看空间占用。"
        case .treemap: return "用面积看空间，点击区块继续探索。"
        case .uninstall: return "查看应用与关联文件，确认后移入废纸篓。"
        case .junk: return "查找可能遗留的文件，由你决定是否保留。"
        case .updates: return "按需检查应用声明的更新来源。"
        case .settings: return "调整外观与扫描偏好。"
        }
    }

    private var scanStatus: some View {
        HStack(spacing: 6) {
            StatusDot(color: statusColor)
            Text(statusText).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(statusColor.opacity(0.07), in: Capsule())
        .modifier(FileCleanGlassSurface(cornerRadius: 999))
    }

    private var statusColor: Color {
        switch store.scanStage {
        case .enumerating, .hashing: return Palette.accent
        case .cancelled: return Palette.orange
        case .failed: return Palette.red
        case .finishedAt, .idle: return Palette.accent
        }
    }

    private var statusText: String {
        switch store.scanStage {
        case .idle: return "未扫描"
        case .enumerating:
            return "扫描中 · \(Format.count(store.progress.filesExamined)) 文件 \(Format.bytes(store.progress.bytesExamined))"
        case .hashing: return "比对中"
        case .finishedAt:
            if let result = store.result {
                return "已扫描 · \(Format.count(result.totalFiles)) 文件"
            }
            return "已扫描"
        case .cancelled: return "已取消"
        case .failed: return "扫描失败"
        }
    }

    private func banner(_ text: String, symbol: String, color: Color, isError: Bool, dismissible: Bool = true) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 12)).lineLimit(3)
            Spacer()
            if dismissible {
                Button {
                    if isError { store.error = nil } else { store.notice = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isError ? "关闭错误" : "关闭提示")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 24).padding(.bottom, 12)
    }

    private var staleBanner: some View {
        banner(
            "文件已处理。目录体积仍来自原扫描，请重新扫描以更新统计。",
            symbol: "clock.badge.exclamationmark", color: Palette.orange, isError: false, dismissible: false)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Image(systemName: store.processingDeletion ? "hourglass" : "lock.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.accent)
            if store.scanning {
                Text(store.progress.currentPath.isEmpty ? "正在读取目录" : store.progress.currentPath)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let result = store.result {
                Text("扫描于 \(Format.date(result.finishedAt)) · 耗时 \(String(format: "%.1f", result.scannedDuration)) 秒 · 不可读目录 \(Format.count(result.inaccessiblePaths.count)) 个")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("扫描为只读操作；只有经确认的删除才会改动文件。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 12)
        .background(Palette.sidebar)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProductIcon(size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FileClean").font(.system(size: 18, weight: .semibold)).tracking(-0.5)
                    Text("cduyzh · 文件整理").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 40).padding(.bottom, 22)

            ForEach(sidebarSections, id: \.section) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.section).font(.system(size: 9.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.top, 10)
                    ForEach(group.pages) { page in
                        SidebarRow(
                            symbol: page.symbol, title: page.title, badge: badge(for: page),
                            selected: store.page == page) {
                            store.navigate(page)
                        }
                    }
                }
            }
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: 8) {
                Label("废纸篓优先", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                Text("清理前由你确认，\n需要时可从废纸篓找回。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13).background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14).padding(.bottom, 12)
            Divider().padding(.horizontal, 16)
            Button {
                store.showReleaseHistory = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 11, weight: .medium))
                    Text("v\(AppVersion.current.version)（构建 \(AppVersion.current.build)）")
                        .font(.system(size: 10)).monospacedDigit()
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .help("查看更新历史")
        }
        .frame(width: 216)
        .background(Palette.sidebar)
    }

    private var sidebarSections: [(section: String, pages: [FileCleanStore.Page])] {
        [("磁盘", [.overview, .treemap, .tree, .large, .duplicates]),
         ("应用", [.uninstall, .junk, .updates]),
         ("通用", [.settings])]
    }

    private func badge(for page: FileCleanStore.Page) -> String? {
        switch page {
        case .large:
            return store.largeFiles.isEmpty ? nil : Format.count(store.largeFiles.count)
        case .duplicates:
            return store.duplicateGroups.isEmpty ? nil : Format.count(store.duplicateGroups.count)
        case .updates:
            return store.availableUpdates.isEmpty ? nil : Format.count(store.availableUpdates.count)
        case .junk:
            return store.orphans.isEmpty ? nil : Format.count(store.orphans.count)
        default:
            return nil
        }
    }
}

private struct SidebarRow: View {
    let symbol: String
    let title: String
    let badge: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Palette.accent : Palette.muted)
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 9.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(selected ? Palette.accent : .secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((selected ? Palette.accent : Color.secondary).opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(selected ? Palette.accent : Color.primary.opacity(0.82))
            .background(selected ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .leading) { if selected { Capsule().fill(Palette.accent).frame(width: 3, height: 17).padding(.leading, 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
