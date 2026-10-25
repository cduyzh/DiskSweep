import SwiftUI
import FileCleanCore

/// 详情面板：展示当前选中文件的真实元数据。
struct InspectorView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        ScrollView {
            if let entry = store.selectedEntry {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        SymbolBadge(symbol: entry.category.symbol, tint: entry.category.tint, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            Text(entry.category.title + (entry.isHardlink ? " · 硬链接" : ""))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        row("逻辑大小", Format.bytes(entry.size))
                        if let allocated = entry.allocatedSize {
                            row("实际占用", Format.bytes(allocated))
                        }
                        row("修改时间", Format.date(entry.modifiedAt))
                        row("创建时间", Format.date(entry.createdAt))
                        if let count = entry.linkCount {
                            row("硬链接数", Format.count(count))
                        }
                        if let inode = entry.inode {
                            row("资源标识", String(inode))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("路径").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(entry.path).font(.system(size: 10.5)).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Button { store.revealInFinder(entry) } label: { Label("在访达中显示", systemImage: "folder") }
                        Button { store.copyPath(entry) } label: { Label("复制完整路径", systemImage: "doc.on.doc") }
                        Divider()
                        Button { store.requestDeletion([entry]) } label: { Label("移入废纸篓…", systemImage: "trash") }
                            .foregroundStyle(Palette.accent).disabled(store.processingDeletion || store.scanning)
                        Text("可恢复，不会直接删除。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    if entry.isHardlink {
                        Text("该文件与其他路径共享同一物理数据（硬链接）；删除单一路径不会立即释放空间。")
                            .font(.system(size: 10)).foregroundStyle(Palette.orange)
                    }
                    if let allocated = entry.allocatedSize, allocated != entry.size {
                        Text("实际占用与逻辑大小不同：稀疏文件、APFS 克隆或压缩会减少实际分配的存储块。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            } else {
                EmptyState(symbol: "sidebar.right", title: "未选择文件",
                           message: "在大文件或重复文件列表中选择一项查看详情。")
            }
        }
        .background(Palette.surface)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 0.5) }
    }
}
