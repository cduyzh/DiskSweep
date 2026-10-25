import SwiftUI
import FileCleanCore

/// 垃圾清理：反向搜索无主条目（孤儿缓存 / 偏好 / 容器 / 启动项）。
struct JunkView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if store.orphansScanning {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("正在反查条目归属…").font(.system(size: 13, weight: .semibold))
                    Text("枚举 Library 常驻位置的顶层条目，与全部已安装应用的标识符缓存比对。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.orphans.isEmpty {
                EmptyState(symbol: "xmark.bin", title: "尚未检测",
                           message: "检测会枚举用户 Library 并比对全部已安装应用；结果为启发式，清理前请逐项确认。")
            } else {
                orphanList
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            ToolButton(symbol: "arrow.clockwise", label: "重新检测") { store.runOrphanScan() }
                .disabled(store.orphansScanning)
            Text(store.orphans.isEmpty ? "" : "\(Format.count(store.orphans.count)) 个无主条目 · \(Format.bytes(totalBytes))")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if !store.orphanSelected.isEmpty {
                let items = store.selectedOrphans
                let bytes = items.reduce(UInt64(0)) { $0 + $1.sizeBytes }
                Text("已选 \(Format.count(items.count)) 项 · \(Format.bytes(bytes))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent).monospacedDigit()
                Button {
                    store.requestOrphanDeletion(items, mode: .trash)
                    store.orphanSelected = []
                } label: {
                    Label("移入废纸篓", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Palette.accent)
                }.buttonStyle(.plain)

            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var totalBytes: UInt64 {
        store.orphans.reduce(0) { $0 + $1.sizeBytes }
    }

    private var orphanList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("「无主」指名称不匹配任何已安装应用且不属于系统前缀；Apple 与系统条目已自动排除。误判可能存在，删除前请确认。")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }.padding(.bottom, 4)
                ForEach(store.orphans) { item in
                    orphanRow(item)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private func orphanRow(_ item: OrphanItem) -> some View {
        let selected = store.orphanSelected.contains(item.id)
        return HStack(spacing: 10) {
            Button {
                if selected { store.orphanSelected.remove(item.id) }
                else { store.orphanSelected.insert(item.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Palette.accent : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel(selected ? "取消勾选" : "勾选条目")
            Image(systemName: item.kind == .launchAgent ? "bolt" : "folder.badge.questionmark")
                .font(.system(size: 12)).foregroundStyle(Palette.orange)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(item.kind.rawValue).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Palette.muted.opacity(0.1), in: Capsule())
                }
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
}
