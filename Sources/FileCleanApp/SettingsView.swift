import SwiftUI
import FileCleanCore

/// 设置：外观、扫描参数与版本信息。
struct SettingsView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appearanceSection
                scanSection
                safetySection
                versionSection
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("外观")
            Picker("界面外观", selection: $store.appearance) {
                Text("跟随系统").tag(0)
                Text("浅色").tag(1)
                Text("深色").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            Text("选择立即生效并保存；刷新不做排序或数值动画，适合减少动态效果偏好。")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(16).panel()
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("扫描与检测")
            Picker("大文件阈值", selection: $store.largeFileMiB) {
                ForEach([10, 50, 100, 500, 1024], id: \.self) { size in
                    Text(size >= 1024 ? "1 GB" : "\(size) MB").tag(size)
                }
            }
            .frame(width: 320)
            Picker("重复检测最小体积", selection: $store.minDuplicateMiB) {
                ForEach([1, 5, 10, 50, 100], id: \.self) { size in
                    Text(size >= 1024 ? "1 GB" : "\(size) MB").tag(size)
                }
            }
            .frame(width: 320)
            Toggle("跳过隐藏文件与目录", isOn: $store.skipHidden)
            Text("大文件阈值会立即筛选已有候选；降低到本轮候选收集下限以下时需重新扫描。其他扫描选项在下次扫描生效。扫描只读取元数据；重复检测会读取候选文件的数据内容用于哈希比对。")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(16).panel()
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("文件清理与恢复", systemImage: "arrow.uturn.backward.circle")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
            Text("大文件、重复文件、垃圾清理和应用卸载统一移入系统废纸篓。每次处理前确认范围，移动失败则保留原文件并显示原因。")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text("可在访达的废纸篓中恢复文件。移入废纸篓不会立即释放磁盘空间，空间数值以重新扫描与系统报告为准。")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }.padding(16).panel()
    }

    private var versionSection: some View {
        let version = AppVersion.current
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("版本与更新")
            row("当前版本", "\(version.version)（构建 \(version.build)）")
            row("构建时间", version.buildDate)
            row("运行路径", version.runningPath)
            row("来源摘要", version.sourceSummary)
            row("正式安装", version.formallyInstalled ? "是（/Applications）" : "否（开发副本）")
            Button {
                store.showReleaseHistory = true
            } label: {
                Label("查看更新历史", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
            Text("在线更新源尚未配置；应用不冒称“已是远端最新版”。发行包可通过本地打包脚本生成。")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .padding(16).panel()
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                .textSelection(.enabled).multilineTextAlignment(.trailing)
        }
    }
}

/// 更新历史弹窗：与应用内记录同源。
struct ReleaseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    private let history = AppVersion.current.history

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("更新历史").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                }.buttonStyle(.plain).accessibilityLabel("关闭")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(history) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("v\(record.version)（构建 \(record.build)）").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                Text(record.date).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Text(record.title).font(.system(size: 11.5, weight: .medium))
                            Text(record.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                            ForEach(record.highlights, id: \.self) { highlight in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("·").foregroundStyle(Palette.accent)
                                    Text(highlight).font(.system(size: 10.5))
                                }
                            }
                            if !record.notes.isEmpty {
                                Text("使用说明").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                                ForEach(record.notes, id: \.self) { note in
                                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(14).panel()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 520)
    }
}
