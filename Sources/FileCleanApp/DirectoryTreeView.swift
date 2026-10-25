import SwiftUI
import FileCleanCore

/// 目录整理：按真实聚合体积展开的目录树，每层显示占比。
struct DirectoryTreeView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        Group {
            if store.scanning {
                EmptyState(symbol: "hourglass", title: "正在扫描", message: store.progress.currentPath.isEmpty ? "读取目录元数据中" : store.progress.currentPath)
            } else if let result = store.result {
                List {
                    Section {
                        NodeRow(node: result.root, rootSize: result.root.size, depth: 0)
                    } header: {
                        Text(result.rootURL.path)
                    }
                }
                .listStyle(.inset)
            } else {
                EmptyState(symbol: "folder", title: "尚未扫描", message: "先在磁盘概览开始扫描，再回来查看目录体积分布。")
            }
        }
    }
}

private struct NodeRow: View {
    let node: DirectoryNode
    let rootSize: UInt64
    let depth: Int
    @State private var expanded = false
    @State private var hovered = false

    private var fraction: Double {
        rootSize == 0 ? 0 : Double(node.size) / Double(rootSize)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                .frame(width: 10)
                .opacity(node.children.isEmpty ? 0 : 1)
            Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Palette.blue)
            Text(node.name.isEmpty ? "/" : node.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).help(node.path)
            Text("\(Format.count(node.fileCount)) 文件 / \(Format.count(node.directoryCount)) 目录")
                .font(.system(size: 9.5)).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            ProportionBar(fraction: fraction).frame(width: 90)
            Text(Format.bytes(node.size)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .frame(width: 78, alignment: .trailing)
            Text(Format.fraction(fraction)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                .monospacedDigit().frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if !node.children.isEmpty { expanded.toggle() } }
        .background(hovered ? Color.primary.opacity(0.03) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        if expanded {
            ForEach(node.children) { child in
                NodeRow(node: child, rootSize: rootSize, depth: depth + 1)
            }
        }
    }
}
