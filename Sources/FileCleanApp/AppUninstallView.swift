import SwiftUI
import FileCleanCore

/// 应用卸载：应用列表 + 选中应用的残留明细。
/// 残留按标识符匹配 Library 固定位置； Containers 通过元数据精确归属。
struct AppUninstallView: View {
    @EnvironmentObject private var store: FileCleanStore
    @State private var query = ""

    private var filteredApps: [InstalledApp] {
        guard !query.isEmpty else { return store.apps }
        return store.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if store.appsLoading && store.apps.isEmpty {
                EmptyState(symbol: "hourglass", title: "正在读取应用清单", message: "解析 /Applications 与系统位置的 bundle 元数据。")
            } else if store.apps.isEmpty {
                EmptyState(symbol: "app.dashed", title: "未发现应用", message: "确认 /Applications 可读后刷新。")
            } else {
                HStack(spacing: 0) {
                    appList
                    Rectangle().fill(Palette.line).frame(width: 1)
                    detail
                }
            }
        }
        .onAppear { if store.apps.isEmpty { store.loadApps() } }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("搜索应用或 Bundle ID", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
            .padding(.horizontal, 12).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredApps) { app in
                        AppRow(app: app, selected: store.selectedApp?.id == app.id) {
                            store.selectApp(app)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .frame(width: 286)
        .background(Palette.sidebar)
    }

    private var detail: some View {
        Group {
            if let app = store.selectedApp {
                appDetail(app)
            } else {
                EmptyState(symbol: "app.dashed", title: "选择一个应用",
                           message: "查看它的卸载残留；系统应用仅展示，不可卸载。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appDetail(_ app: InstalledApp) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(app)
                    if let reason = AppUninstaller.uninstallBlockedReason(for: app) {
                        blockedCard(app, reason)
                    } else if store.residualScanning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在匹配 Library 位置与容器元数据…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }.padding(14).panel()
                    } else {
                        residualList(app)
                    }
                }
                .padding(20)
            }
            if AppUninstaller.uninstallBlockedReason(for: app) == nil {
                actionBar(app)
            }
        }
    }

    private func header(_ app: InstalledApp) -> some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 17, weight: .semibold))
                    if app.isFromAppStore { tag("App Store", Palette.blue) }
                    if app.isSystem { tag("系统", Palette.muted) }
                }
                Text("\(app.bundleID) · 版本 \(app.version)（构建 \(app.build))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Text(app.bundleURL.path).font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Picker("", selection: $store.residualSensitivity) {
                Text("精确匹配").tag(0)
                Text("增强匹配").tag(1)
            }
            .pickerStyle(.segmented).frame(width: 170)
            .disabled(store.residualScanning)
            .onChange(of: store.residualSensitivity) { _ in store.findResiduals(for: app) }
            ToolButton(symbol: "arrow.clockwise", label: "重新查找残留") { store.findResiduals(for: app) }
                .disabled(store.residualScanning)
        }
    }

    private func blockedCard(_ app: InstalledApp, _ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(Palette.orange)
            Text(reason).font(.system(size: 12))
            Spacer()
        }.padding(14).panel()
    }

    private func residualList(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("残留文件（\(Format.count(store.residuals.count)) 项 · \(Format.bytes(store.residualTotalBytes))）")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("缓存与日志已默认勾选").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if store.residuals.isEmpty {
                Text("未发现可关联的残留；容器归属为精确匹配，其余按名称匹配。")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(12).panel()
            } else {
                ForEach(store.residuals) { item in
                    residualRow(item)
                }
                Text("名称匹配为启发式；勾选前请确认条目确实属于该应用。容器通过系统元数据精确归属。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func residualRow(_ item: ResidualItem) -> some View {
        let selected = store.residualSelected.contains(item.id)
        return HStack(spacing: 10) {
            Button {
                if selected { store.residualSelected.remove(item.id) }
                else { store.residualSelected.insert(item.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Palette.accent : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel(selected ? "取消勾选" : "勾选残留")
            tag(item.kind.rawValue, kindColor(item.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).help(item.path)
                Text(item.path).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Text(Format.bytes(item.sizeBytes)).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
            ToolButton(symbol: "magnifyingglass", label: "在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(Color.primary.opacity(selected ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionBar(_ app: InstalledApp) -> some View {
        let chosen = store.selectedResiduals
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        return HStack(spacing: 12) {
            Text(chosen.isEmpty
                 ? "卸载将移除应用包；勾选的残留一并处理"
                 : "应用包 + \(Format.count(chosen.count)) 项残留 · 合计约 \(Format.bytes(bytes + 4096))")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button {
                store.pendingUninstall = FileCleanStore.PendingUninstall(app: app, residuals: chosen, mode: .trash)
            } label: {
                Label("移入废纸篓并卸载", systemImage: "trash")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)

        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Palette.sidebar)
    }

    private func kindColor(_ kind: ResidualItem.Kind) -> Color {
        switch kind {
        case .caches: return Palette.accent
        case .logs: return Palette.orange
        case .preferences: return Palette.blue
        case .containers, .groupContainers: return Palette.purple
        default: return Palette.muted
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9.5, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                    .resizable().frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                    Text(app.version).font(.system(size: 9.5)).foregroundStyle(.tertiary).monospacedDigit()
                }
                Spacer()
                if app.isSystem {
                    Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .help("系统应用，不可卸载")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(selected ? Palette.accent : Color.primary.opacity(0.85))
            .background(selected ? Palette.accent.opacity(0.09) : Color.primary.opacity(hovered ? 0.03 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

