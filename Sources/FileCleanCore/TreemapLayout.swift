import Foundation

/// Squarified treemap 布局（Bruls / Huizing / van Wijk 2000）：
/// 递归把矩形按子项体积分割，最大化长宽比接近正方形的区块，
/// 避免 slice-and-dice 的细长条。GrandPerspective 的 cushion 效果由视图层叠加。
public struct TreemapTile: Identifiable, Sendable {
    public let rect: CGRect
    public let path: String
    public let name: String
    public let size: UInt64
    public let depth: Int
    public var id: String { path }
}

public enum TreemapLayout {

    /// 为目录树的一个层级生成 tile。归一化到 0...1 坐标，由视图缩放。
    /// - Parameters:
    ///   - node: 当前展示的目录节点。
    ///   - childLimit: 每层最多展示的子目录数（其余合并为"其他"）。
    public static func tiles(for node: DirectoryNode, childLimit: Int = 40) -> [TreemapTile] {
        var candidates: [(index: Int, name: String, size: UInt64)] = []
        for (index, child) in node.children.enumerated() where child.size > 0 {
            candidates.append((index, child.name, child.size))
        }
        guard !candidates.isEmpty else { return [] }
        var kept = Array(candidates.prefix(childLimit))
        var overflow: UInt64 = 0
        if candidates.count > childLimit {
            overflow = candidates.suffix(candidates.count - childLimit).reduce(0) { $0 + $1.size }
        }

        var rects: [(name: String, size: UInt64, index: Int)] =
            kept.map { (name: $0.name, size: $0.size, index: $0.index) }
        if overflow > 0 {
            rects.append((name: "其他 \(candidates.count - childLimit) 项", size: overflow, index: -1))
        }
        rects.sort { $0.size > $1.size }

        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let laid = squarify(sizes: rects.map(\.size), in: unit)
        return zip(rects, laid).map { entry, rect in
            TreemapTile(rect: rect,
                        path: entry.index >= 0 ? node.children[entry.index].path : node.path + "/…",
                        name: entry.name, size: entry.size, depth: node.depth + 1)
        }
    }

    /// squarify 主体：按行填充，每行选择让最差长宽比最小的方向。
    static func squarify(sizes: [UInt64], in rect: CGRect) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        var remaining = Array(sizes)
        var output: [CGRect] = []
        var bounds = rect
        while !remaining.isEmpty {
            let total = remaining.reduce(UInt64(0)) { $0 + $1 }
            guard total > 0 else {
                // 体积为 0 的尾部全部给零尺寸区块，避免除零。
                output.append(CGRect.zero)
                remaining.removeFirst()
                continue
            }
            let isWide = bounds.width >= bounds.height
            let side = isWide ? bounds.height : bounds.width
            // 选出本行：逐个加入，只要最差长宽比仍在改善。
            var row: [UInt64] = []
            var bestRatio: Double = .infinity
            var rowEnd = 0
            for (index, size) in remaining.enumerated() {
                let candidate = row + [size]
                let ratio = worstRatio(candidate, side: side, total: total)
                if ratio <= bestRatio || row.isEmpty {
                    bestRatio = ratio
                    row = candidate
                    rowEnd = index + 1
                } else {
                    break
                }
            }
            let rowTotal = row.reduce(UInt64(0)) { $0 + $1 }
            let fraction = Double(rowTotal) / Double(total)
            let thickness = (isWide ? bounds.width : bounds.height) * fraction
            var offset: CGFloat = 0
            for size in row {
                let share = Double(size) / Double(rowTotal)
                let length = side * share
                let frame = isWide
                    ? CGRect(x: bounds.minX, y: bounds.minY + offset, width: thickness, height: length)
                    : CGRect(x: bounds.minX + offset, y: bounds.minY, width: length, height: thickness)
                output.append(frame)
                offset += length
            }
            remaining.removeFirst(rowEnd)
            bounds = isWide
                ? CGRect(x: bounds.minX + thickness, y: bounds.minY,
                         width: max(bounds.width - thickness, 0), height: bounds.height)
                : CGRect(x: bounds.minX, y: bounds.minY + thickness,
                         width: bounds.width, height: max(bounds.height - thickness, 0))
        }
        return output
    }

    /// 一行区块的最差长宽比。
    static func worstRatio(_ row: [UInt64], side: CGFloat, total: UInt64) -> Double {
        guard !row.isEmpty, side > 0, total > 0 else { return .infinity }
        let rowTotal = row.reduce(UInt64(0)) { $0 + $1 }
        let thickness = side * CGFloat(Double(rowTotal) / Double(total))
        var worst: Double = 0
        for size in row {
            let length = side * CGFloat(Double(size) / Double(rowTotal))
            if length <= 0 || thickness <= 0 { continue }
            worst = max(worst, max(thickness / length, length / thickness))
        }
        return worst
    }
}
