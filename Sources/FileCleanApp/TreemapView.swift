import SwiftUI
import FileCleanCore

/// 空间视图：squarified treemap + 坐垫高光。面积与目录真实聚合体积成正比，
/// 点击区块下钻，面包屑返回；数据复用主扫描结果，不做二次扫描。
struct TreemapView: View {
    @EnvironmentObject private var store: FileCleanStore
    @State private var hover: TreemapTile?
    @State private var hoverPoint: CGPoint = .zero
    @State private var proxySize: CGSize = .zero

    private var currentNode: DirectoryNode? {
        guard let root = store.result?.root else { return nil }
        var node = root
        for path in store.treemapPathStack {
            guard let next = node.children.first(where: { $0.path == path }) else { break }
            node = next
        }
        return node
    }

    private let palette: [Color] = [
        Palette.accent, Palette.blue, Palette.purple, Palette.orange,
        Color(light: 0x4E9A8B, dark: 0x7BC4B4), Color(light: 0x7A9DB8, dark: 0xA3C1D8),
        Color(light: 0x9A86C0, dark: 0xC0AEE2), Color(light: 0xB08A50, dark: 0xD8B57E),
    ]

    var body: some View {
        Group {
            if let node = currentNode {
                VStack(spacing: 0) {
                    breadcrumb(node)
                    canvas(node)
                        .padding(.horizontal, 24).padding(.bottom, 24)
                }
            } else if store.scanning {
                EmptyState(symbol: "hourglass", title: "正在扫描", message: "扫描完成后可查看空间视图。")
            } else {
                EmptyState(symbol: "square.grid.3x3", title: "尚未扫描",
                           message: "空间视图基于主扫描结果绘制；先在磁盘概览开始扫描。")
            }
        }
    }

    private func breadcrumb(_ node: DirectoryNode) -> some View {
        HStack(spacing: 8) {
            ToolButton(symbol: "chevron.left", label: "返回上层") {
                if !store.treemapPathStack.isEmpty { store.treemapPathStack.removeLast() }
            }.disabled(store.treemapPathStack.isEmpty)
            Button(store.result?.root.name.isEmpty ?? true ? "/" : store.result!.root.name) {
                store.treemapPathStack = []
            }.buttonStyle(.link).font(.system(size: 11))
            ForEach(store.treemapPathStack.suffix(3), id: \.self) { path in
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                Button(URL(fileURLWithPath: path).lastPathComponent) {
                    if let index = store.treemapPathStack.firstIndex(of: path) {
                        store.treemapPathStack = Array(store.treemapPathStack.prefix(index + 1))
                    }
                }.buttonStyle(.link).font(.system(size: 11))
            }
            Spacer()
            Text("\(node.name.isEmpty ? "/" : node.name) · \(Format.bytes(node.size)) · \(Format.count(node.fileCount)) 文件")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private func canvas(_ node: DirectoryNode) -> some View {
        let tiles = TreemapLayout.tiles(for: node)
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for (index, tile) in tiles.enumerated() {
                        let rect = CGRect(x: tile.rect.minX * size.width,
                                          y: tile.rect.minY * size.height,
                                          width: tile.rect.width * size.width,
                                          height: tile.rect.height * size.height)
                        guard rect.width > 2, rect.height > 2 else { continue }
                        drawCushion(context: context, rect: rect,
                                    color: palette[index % palette.count],
                                    depth: tile.depth)
                        if rect.width > 44, rect.height > 16 {
                            let label = "\(tile.name)  \(Format.bytes(tile.size))"
                            context.draw(
                                Text(label).font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.92)),
                                at: CGPoint(x: rect.midX, y: rect.minY + 8))
                        }
                    }
                }
                if let hover {
                    tooltip(hover)
                        .fixedSize()
                        .position(x: min(max(hoverPoint.x + 14, 100), max(proxySize.width - 100, 100)),
                                  y: min(max(hoverPoint.y + 16, 40), max(proxySize.height - 30, 40)))
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line, lineWidth: 1))
            .trackingSize($proxySize)
            .onContinuousHover { phase in
                guard case .active(let location) = phase else {
                    hover = nil
                    return
                }
                hoverPoint = location
                hover = GeometryReaderProxy(size: proxySize).tile(at: location, in: tiles)
            }
            .onTapGesture { location in
                if let tile = GeometryReaderProxy(size: proxySize).tile(at: location, in: tiles),
                   let child = node.children.first(where: { $0.path == tile.path }) {
                    store.treemapPathStack.append(child.path)
                }
            }
            Text("面积与目录体积成正比 · 点击区块下钻 · 面包屑返回；不构成清理建议")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 8)
        }
    }

    /// 坐垫效果：底色 + 顶部左上高光 + 内描边，层级越深高光越弱。
    private func drawCushion(context: GraphicsContext, rect: CGRect, color: Color, depth: Int) {
        let inset = rect.insetBy(dx: 0.75, dy: 0.75)
        let path = Path(roundedRect: inset, cornerRadius: 2.5)
        context.fill(path, with: .color(color.opacity(0.88)))
        let highlight = Path(roundedRect: inset.insetBy(dx: inset.width * 0.08, dy: inset.height * 0.08),
                             cornerRadius: 2)
        context.fill(highlight, with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.28 / Double(depth)), Color.white.opacity(0.02)]),
            startPoint: CGPoint(x: inset.minX, y: inset.minY),
            endPoint: CGPoint(x: inset.midX, y: inset.midY)))
        context.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 0.8)
    }

    private func tooltip(_ tile: TreemapTile) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tile.name).font(.system(size: 11, weight: .semibold))
            Text(tile.path).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            Text(Format.bytes(tile.size)).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
        }
        .padding(8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
    }
}

/// hitTest 的辅助：把坐标换算与 tiles 比对抽离出来。
private struct GeometryReaderProxy {
    let size: CGSize

    func tile(at point: CGPoint, in tiles: [TreemapTile]) -> TreemapTile? {
        guard size.width > 0, size.height > 0 else { return nil }
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        return tiles.first { $0.rect.contains(normalized) }
    }
}

/// 记录画布尺寸的包装视图。
extension View {
    func trackingSize(_ size: Binding<CGSize>) -> some View {
        background(GeometryReader { geometry in
            Color.clear.onAppear { size.wrappedValue = geometry.size }
                .onChange(of: geometry.size) { _, newSize in size.wrappedValue = newSize }
        })
    }
}
