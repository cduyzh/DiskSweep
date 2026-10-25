#!/usr/bin/env swift
import AppKit
import Foundation

// 原创矢量绘制，所有尺寸均由 1024 点设计坐标直接重绘。
// 主题：分类文件夹 + 空间分区 + 单枚亮点，对应「查看 · 归类 · 整理」。
// 用法：swift scripts/generate_icon.swift [资源目录]
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

func gradient(_ path: NSBezierPath, _ first: UInt32, _ last: UInt32, angle: CGFloat = -90) {
    NSGradient(starting: color(first), ending: color(last))!.draw(in: path, angle: angle)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "IconRenderer", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    // A quiet mint tile with one recognizable folder silhouette.
    let plate = rounded(72, 72, 880, 880, 198)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 22, color: color(0x143C38, 0.18).cgColor)
    gradient(plate, 0xF3FFF9, 0xCDE9DF)
    cg.restoreGState()
    plate.lineWidth = 3
    color(0xFFFFFF, 0.9).setStroke()
    plate.stroke()

    let back = NSBezierPath()
    back.move(to: NSPoint(x: 212, y: 670))
    back.curve(to: NSPoint(x: 256, y: 714), controlPoint1: NSPoint(x: 212, y: 697), controlPoint2: NSPoint(x: 231, y: 714))
    back.line(to: NSPoint(x: 398, y: 714))
    back.curve(to: NSPoint(x: 446, y: 678), controlPoint1: NSPoint(x: 426, y: 714), controlPoint2: NSPoint(x: 429, y: 678))
    back.line(to: NSPoint(x: 778, y: 678))
    back.curve(to: NSPoint(x: 822, y: 634), controlPoint1: NSPoint(x: 805, y: 678), controlPoint2: NSPoint(x: 822, y: 659))
    back.line(to: NSPoint(x: 822, y: 294))
    back.curve(to: NSPoint(x: 778, y: 250), controlPoint1: NSPoint(x: 822, y: 267), controlPoint2: NSPoint(x: 805, y: 250))
    back.line(to: NSPoint(x: 256, y: 250))
    back.curve(to: NSPoint(x: 212, y: 294), controlPoint1: NSPoint(x: 231, y: 250), controlPoint2: NSPoint(x: 212, y: 267))
    back.close()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 26, color: color(0x154E44, 0.22).cgColor)
    gradient(back, 0x217D69, 0x14564D)
    cg.restoreGState()

    // Three organized files give the mark its classification motif.
    let sheets: [(CGFloat, CGFloat, UInt32)] = [(270, 10, 0xB1D7EE), (383, 0, 0xFBFEFC), (496, -10, 0xF4DC9C)]
    for (x, rotation, hex) in sheets {
        cg.saveGState()
        cg.translateBy(x: x + 85, y: 510)
        cg.rotate(by: rotation * .pi / 180)
        let sheet = rounded(-85, -120, 170, 268, 23)
        cg.setShadow(offset: CGSize(width: 0, height: -5), blur: 9, color: color(0x123E34, 0.16).cgColor)
        gradient(sheet, hex, 0xE6F1EB)
        cg.setShadow(offset: .zero, blur: 0)
        color(0x27675B, 0.22).setFill()
        rounded(-51, 84, 78, 10, 5).fill()
        rounded(-51, 60, 103, 10, 5).fill()
        cg.restoreGState()
    }

    let front = NSBezierPath()
    front.move(to: NSPoint(x: 177, y: 524))
    front.curve(to: NSPoint(x: 222, y: 566), controlPoint1: NSPoint(x: 174, y: 550), controlPoint2: NSPoint(x: 194, y: 566))
    front.line(to: NSPoint(x: 803, y: 566))
    front.curve(to: NSPoint(x: 848, y: 519), controlPoint1: NSPoint(x: 832, y: 566), controlPoint2: NSPoint(x: 851, y: 546))
    front.line(to: NSPoint(x: 821, y: 282))
    front.curve(to: NSPoint(x: 768, y: 236), controlPoint1: NSPoint(x: 818, y: 254), controlPoint2: NSPoint(x: 799, y: 236))
    front.line(to: NSPoint(x: 258, y: 236))
    front.curve(to: NSPoint(x: 205, y: 282), controlPoint1: NSPoint(x: 227, y: 236), controlPoint2: NSPoint(x: 208, y: 254))
    front.close()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0x163E32, 0.2).cgColor)
    gradient(front, 0x46C5A1, 0x17846E)
    cg.restoreGState()
    color(0x8FEBCB, 0.7).setStroke()
    front.lineWidth = 3
    front.stroke()

    // The simple segmented disk map stays legible at Dock sizes.
    color(0xF5FFF9, 0.96).setFill()
    rounded(358, 335, 88, 136, 19).fill()
    rounded(460, 414, 132, 57, 16).fill()
    color(0xBAF5DF, 0.9).setFill()
    rounded(460, 335, 132, 65, 16).fill()
    color(0xFFFFFF, 0.6).setFill()
    rounded(607, 335, 58, 136, 17).fill()

    // A single sparkle expresses a tidy workspace without a deletion symbol.
    let sparkle = NSBezierPath()
    let x: CGFloat = 780, y: CGFloat = 739, r: CGFloat = 69
    sparkle.move(to: NSPoint(x: x, y: y + r))
    sparkle.curve(to: NSPoint(x: x + r, y: y), controlPoint1: NSPoint(x: x + 12, y: y + 12), controlPoint2: NSPoint(x: x + 12, y: y + 12))
    sparkle.curve(to: NSPoint(x: x, y: y - r), controlPoint1: NSPoint(x: x + 12, y: y - 12), controlPoint2: NSPoint(x: x + 12, y: y - 12))
    sparkle.curve(to: NSPoint(x: x - r, y: y), controlPoint1: NSPoint(x: x - 12, y: y - 12), controlPoint2: NSPoint(x: x - 12, y: y - 12))
    sparkle.curve(to: NSPoint(x: x, y: y + r), controlPoint1: NSPoint(x: x - 12, y: y + 12), controlPoint2: NSPoint(x: x - 12, y: y + 12))
    sparkle.close()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: color(0x477D66, 0.15).cgColor)
    color(0xFCFFED).setFill()
    sparkle.fill()
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconRenderer", code: 2)
    }
    return png
}

let mainIcon = output.appendingPathComponent("AppIcon_1024.png")
try drawIcon(size: 1024).write(to: mainIcon)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }
for base in [16, 32, 128, 256, 512] {
    try drawIcon(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", output.appendingPathComponent("AppIcon.icns").path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconRenderer", code: Int(process.terminationStatus))
}
print("已生成 \(mainIcon.path) 与 AppIcon.icns")
