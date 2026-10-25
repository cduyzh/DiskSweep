import SwiftUI
import FileCleanCore

/// 磁盘概览：卷容量卡片、扫描摘要与一级目录体积排行。
struct DiskOverviewView: View {
    @EnvironmentObject private var store: FileCleanStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                welcomeCard
                volumeCards
                if store.result != nil || store.scanning {
                    summaryCards
                    if let result = store.result {
                        topDirectories(result)
                        if !result.inaccessiblePaths.isEmpty {
                            inaccessibleCard(result.inaccessiblePaths)
                        }
                    }
                }
                snapshotCard
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private var volumeCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("卷容量", symbol: "internaldrive")
            if store.volumes.isEmpty {
                Text("未读取到卷信息").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(store.volumes) { volume in
                    volumeRow(volume)
                }
                Text("容量为系统报告口径，APFS 共享空间与 Finder 可能存在差异；“可用”包含系统可自动清除的空间。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func volumeRow(_ volume: VolumeInfo) -> some View {
        HStack(spacing: 14) {
            SymbolBadge(symbol: volume.isInternal ? "internaldrive" : "externaldrive",
                        tint: volume.isSystem ? Palette.blue : Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(volume.name).font(.system(size: 13, weight: .semibold))
                    if volume.isSystem {
                        tag("系统卷", color: Palette.blue)
                    }
                    if !volume.isInternal {
                        tag("外置", color: Palette.purple)
                    }
                    if let fs = volume.fileSystemType {
                        Text(fs).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                ProportionBar(fraction: volume.totalBytes == 0 ? 0 : Double(volume.usedBytes) / Double(volume.totalBytes),
                              tint: Double(volume.usedBytes) / Double(max(volume.totalBytes, 1)) > 0.85 ? Palette.orange : Palette.accent)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.bytes(volume.usedBytes) + " 已用").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text("共 " + Format.bytes(volume.totalBytes) + " · 可用 " + Format.bytes(volume.availableBytes))
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(14).panel()
    }

    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.metering.unknown").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Text("APFS 本地快照与可清除空间").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                ToolButton(symbol: "arrow.clockwise", label: "刷新快照信息") { store.refreshSnapshots() }
            }
            if let purgeable = store.purgeableBytes {
                HStack(spacing: 12) {
                    statInline("可清除空间（估算）", Format.bytes(purgeable), tint: Palette.blue)
                    Divider().frame(height: 24)
                    statInline("本地快照", Format.count(store.snapshots.count), tint: Palette.purple)
                }
            }
            if !store.snapshots.isEmpty {
                ForEach(store.snapshots.prefix(4)) { snapshot in
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Text(snapshot.displayDate).font(.system(size: 10.5)).monospacedDigit()
                        Text(snapshot.rawName).font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                if store.snapshots.count > 4 {
                    Text("等 \(Format.count(store.snapshots.count)) 个快照")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
            } else if let snapshotError = store.snapshotError {
                Text("快照信息不可读取：\(snapshotError)").font(.system(size: 10.5)).foregroundStyle(Palette.orange)
            } else if store.snapshots.isEmpty {
                Text("未发现本地快照。").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Text("清理文件后空间未增长，通常是本地快照仍引用旧数据块。删除快照需要管理员权限，本工具不提权；可在「磁盘工具 → 显示 APFS 快照」或终端 tmutil 处理。可清除空间为估算口径，与磁盘工具可能不同。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(14).panel()
        .onAppear { if store.snapshots.isEmpty && store.snapshotError == nil { store.refreshSnapshots() } }
    }

    private func statInline(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
        }
    }

    private var welcomeCard: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Label("从了解空间开始", systemImage: "sparkle")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                Text("腾出空间，\n也整理一下思绪。")
                    .font(.system(size: 29, weight: .semibold)).tracking(-0.7).lineSpacing(4).foregroundStyle(Palette.ink)
                Text("查看文件夹占用，按种类找到大文件。\n所有清理先经你确认，再移入可恢复的废纸篓。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                HStack(spacing: 14) {
                    Button {
                        if store.scanning { store.cancelScan() } else { store.startScan() }
                    } label: {
                        Label(store.scanning ? "停止扫描" : "扫描用户目录", systemImage: store.scanning ? "stop.fill" : "magnifyingglass")
                    }.buttonStyle(PrimaryButtonStyle()).disabled(store.processingDeletion)
                    Button("选择文件夹…") { store.chooseScanDirectory() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                        .disabled(store.scanning || store.processingDeletion)
                }.padding(.top, 3)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                ProductIcon(size: 176)
                Label("只读扫描 · 确认后整理", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(Palette.accent)
            }.frame(width: 210)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Palette.surface, Palette.accent.opacity(0.065)], startPoint: .leading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.accent.opacity(0.12), lineWidth: 1))
    }

    private var summaryCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("扫描结果", symbol: "chart.bar.doc.horizontal")
            if store.scanning {
                HStack(spacing: 14) {
                    SymbolBadge(symbol: "magnifyingglass", tint: Palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在读取 \(store.progress.currentPath.isEmpty ? "目录" : store.progress.currentPath)")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text("\(Format.count(store.progress.filesExamined)) 个文件 · \(Format.bytes(store.progress.bytesExamined)) · \(Format.count(store.progress.directoriesExamined)) 个目录")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    ProgressView().controlSize(.small)
                }
                .padding(14).panel()
            } else if let result = store.result {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard("用户目录体积", Format.bytes(result.totalLogicalBytes), symbol: "externaldrive.fill", tint: Palette.accent)
                    statCard("文件总数", Format.count(result.totalFiles), symbol: "doc.fill", tint: Palette.purple)
                    statCard("目录总数", Format.count(result.totalDirectories), symbol: "folder.fill", tint: Palette.blue)
                }
                HStack(spacing: 10) {
                    Button { store.navigate(.large) } label: {
                        Label("按种类查看 \(Format.count(store.largeFiles.count)) 个大文件", systemImage: "square.grid.2x2")
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                    Spacer()
                }
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text("体积为逻辑大小合计（硬链接只计一次）；符号链接不计入。\(Format.count(result.symlinkSkipped)) 个符号链接与 \(Format.count(result.hardlinkSkipped)) 个重复硬链接未计入。")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func statCard(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 21, weight: .semibold)).monospacedDigit()
            }
            Spacer()
        }
        .padding(14).panel()
    }

    private func topDirectories(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("一级目录占用", symbol: "square.split.2x2")
            let total = max(result.root.size, 1)
            ForEach(result.root.children.prefix(10)) { child in
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(Palette.blue).frame(width: 16)
                    Text(child.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        .help(child.path)
                    Text("\(Format.count(child.fileCount)) 文件").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    ProportionBar(fraction: Double(child.size) / Double(total)).frame(width: 140)
                    Text(Format.bytes(child.size)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .frame(width: 76, alignment: .trailing)
                    Text(Format.fraction(Double(child.size) / Double(total))).font(.system(size: 10)).foregroundStyle(.secondary)
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            }
            Button {
                store.navigate(.tree)
            } label: {
                Label("在目录整理中展开全部层级", systemImage: "arrow.right.circle")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func inaccessibleCard(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("不可读取的目录（\(Format.count(paths.count))）", symbol: "lock.shield")
            ForEach(paths.prefix(8), id: \.self) { path in
                Text(path).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if paths.count > 8 {
                Text("等 \(Format.count(paths.count)) 个目录；受系统权限保护，未计入统计。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(14).panel()
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9.5, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}
