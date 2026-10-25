import SwiftUI
import FileCleanCore

/// 软件更新检查：Sparkle 自更新源与 App Store lookup。
/// 仅在用户显式点击时发起网络请求；无更新源的应用如实标注。
struct UpdatesView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if store.apps.isEmpty && !store.appsLoading {
                EmptyState(symbol: "arrow.triangle.2.circlepath", title: "正在读取应用清单",
                           message: "更新检查基于已安装应用的 bundle 元数据。")
            } else if store.appsLoading {
                EmptyState(symbol: "hourglass", title: "正在读取应用清单", message: "解析各应用的 bundle 元数据。")
            } else if store.updateStatuses.isEmpty && !store.updatesChecking {
                idleCard
            } else {
                statusList
            }
        }
        .onAppear { if store.apps.isEmpty { store.loadApps() } }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            ToolButton(symbol: store.updatesChecking ? "stop.circle" : "arrow.triangle.2.circlepath",
                       label: store.updatesChecking ? "检查中…" : "检查全部应用") {
                if !store.updatesChecking { store.checkUpdates() }
            }.disabled(store.updatesChecking)
            if store.updatesChecking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("已查询 \(Format.count(store.updateStatuses.count)) / \(Format.count(store.uninstallableApps.count))")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                }
            } else if !store.availableUpdates.isEmpty {
                Text("\(Format.count(store.availableUpdates.count)) 个应用有可用更新")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.orange).monospacedDigit()
            }
            Spacer()
            if !store.apps.isEmpty {
                Text("\(Format.count(store.uninstallableApps.count)) 个可检查应用（不含系统应用）")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var idleCard: some View {
        VStack(spacing: 14) {
            SymbolBadge(symbol: "arrow.triangle.2.circlepath", tint: Palette.blue, size: 44)
            Text("检查软件更新").font(.system(size: 15, weight: .semibold))
            Text("两类真实来源：内置 Sparkle 自更新源（RSS appcast）与 App Store 应用（公开 lookup 接口）。\n无更新源的应用会如实标注，不冒称“已是最新”。点击检查才会发起网络请求。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                store.checkUpdates()
            } label: {
                Label("开始检查", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).panel().padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var statusList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.uninstallableApps) { app in
                    if let status = store.updateStatuses[app.id] {
                        statusRow(app, status)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private func statusRow(_ app: InstalledApp, _ status: UpdateStatus) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(app.bundleID) · 当前 \(app.version)")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary).monospacedDigit()
            }
            Spacer()
            stateBadge(status, current: app.version)
            Text(status.source).font(.system(size: 9.5)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func stateBadge(_ status: UpdateStatus, current: String) -> some View {
        switch status.state {
        case .updateAvailable(let latest):
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 11))
                Text("\(current) → \(latest)").font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Palette.orange)
        case .upToDate:
            Label("已最新", systemImage: "checkmark.circle")
                .font(.system(size: 10.5)).foregroundStyle(Palette.accent)
        case .noFeed:
            Text("无更新源").font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .unknown:
            Text("无结果").font(.system(size: 10.5)).foregroundStyle(.secondary)
        case .failed(let message):
            Text("失败：\(message)").font(.system(size: 10)).foregroundStyle(Palette.red).lineLimit(1)
        }
    }
}
