import SwiftUI
import AppKit
import FileCleanCore

enum Palette {
    static let accent = Color(light: 0x157F70, dark: 0x6AD6BE)
    static let background = Color(light: 0xF5F7F8, dark: 0x191E22)
    static let sidebar = Color(light: 0xEAF0EF, dark: 0x131A1D)
    static let surface = Color(light: 0xFFFFFF, dark: 0x22292D)
    static let ink = Color(light: 0x123D38, dark: 0xD6F3EB)
    static let line = Color.primary.opacity(0.075)
    static let orange = Color(light: 0xC27834, dark: 0xEAB16D)
    static let purple = Color(light: 0x8170C6, dark: 0xB5A0F2)
    static let blue = Color(light: 0x548BC4, dark: 0x89B7EB)
    static let red = Color(light: 0xBC5A5A, dark: 0xE59B9B)
    static let muted = Color(light: 0x707983, dark: 0x929CA7)
}

extension FileCategory {
    var tint: Color {
        switch self {
        case .video: return Palette.purple
        case .audio: return Palette.orange
        case .image: return Color(light: 0xB35F83, dark: 0xE69CBD)
        case .document: return Palette.blue
        case .archive: return Palette.orange
        case .installer: return Palette.accent
        case .development: return Color(light: 0x54776F, dark: 0x96BDB4)
        case .virtualMachine: return Palette.purple
        case .other: return Palette.muted
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(light: 0xFFFFFF, dark: 0x12372F))
                .padding(.horizontal, 15).padding(.vertical, 10)
                .background(Palette.accent.opacity(configuration.isPressed ? 0.8 : (hover ? 0.9 : 1)), in: RoundedRectangle(cornerRadius: 9))
                .opacity(enabled ? 1 : 0.35)
                .onHover { hover = $0 }
        }
    }
}

struct ProductIcon: View {
    var size: CGFloat = 40
    var body: some View {
        if let url = Bundle.main.url(forResource: "AppIcon_1024", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
        } else {
            SymbolBadge(symbol: "folder.fill", size: size)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func panel(radius: CGFloat = 12) -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.line, lineWidth: 1))
    }
}

struct SymbolBadge: View {
    let symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

struct ToolButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }
            .buttonStyle(QuietButtonStyle(selected: selected))
            .help(label).accessibilityLabel(label)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration, selected: selected)
    }
    private struct QuietButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Palette.accent : Color.secondary)
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : (hover || selected ? 0.05 : 0)), in: RoundedRectangle(cornerRadius: 7))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

struct StatusDot: View {
    var color: Color = Palette.accent
    var body: some View { Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true) }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            SymbolBadge(symbol: symbol, size: 48)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 水平占比条：显示单项在总量中的真实比例，不做动画。
struct ProportionBar: View {
    let fraction: Double
    var tint: Color = Palette.accent
    var track: Color = Palette.line
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).fill(track)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(tint)
                    .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

enum Format {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
    private static let counter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    static func count(_ value: Int) -> String {
        counter.string(from: NSNumber(value: value)) ?? String(value)
    }
    static func date(_ date: Date?) -> String {
        guard let date else { return "不可读取" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    static func fraction(_ value: Double) -> String {
        String(format: "%.1f %%", min(max(value, 0), 1) * 100)
    }
}
