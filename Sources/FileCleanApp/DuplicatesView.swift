import SwiftUI
import FileCleanCore

/// 重复文件：按内容摘要分组的真实重复，每组勾选要删除的副本。
struct DuplicatesView: View {
    @EnvironmentObject private var store: FileCleanStore
    @State private var query = ""
    /// 组内待删除路径：group 摘要前缀 + 文件路径。
    @State private var marked = Set<String>()

    private var filteredGroups: [DuplicateGroup] {
        guard !query.isEmpty else { return store.duplicateGroups }
        return store.duplicateGroups.filter { group in
            group.files.contains { $0.path.localizedCaseInsensitiveContains(query) }
        }
    }

    private var markedEntries: [FileEntry] {
        var result: [FileEntry] = []
        for group in store.duplicateGroups {
            for file in group.files where marked.contains(file.id) {
                result.append(file)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            switch store.duplicatesStage {
            case .idle:
                if store.result == nil {
                    EmptyState(symbol: "square.on.square", title: "先完成一次扫描", message: "重复检测基于扫描收集的同尺寸候选文件。")
                } else {
                    idleCard
                }
            case .running:
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("正在比对重复文件").font(.system(size: 13, weight: .semibold))
                    Text("采样哈希过滤后，仅对同尺寸候选执行全量 SHA-256；大文件较多时需要一些时间。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyState(symbol: "exclamationmark.triangle", title: "检测失败", message: message)
            case .done:
                if filteredGroups.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "没有检测到重复文件",
                               message: "体积 ≥ \(Format.bytes(UInt64(store.minDuplicateMiB) << 20)) 的候选中，没有内容完全一致的文件。")
                } else {
                    groupList
                }
            }
        }
    }

    private var idleCard: some View {
        VStack(spacing: 14) {
            SymbolBadge(symbol: "dot.scope", size: 44)
            Text("运行重复文件检测").font(.system(size: 15, weight: .semibold))
            Text("三级过滤：体积分组 → 采样哈希 → 全量 SHA-256。\n候选 \(Format.count(store.result?.candidates.count ?? 0)) 个文件（体积 ≥ \(Format.bytes(UInt64(store.minDuplicateMiB) << 20))）。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                store.runDuplicateScan()
            } label: {
                Label("开始检测", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).panel().padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("搜索重复文件路径", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }.buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
            .frame(width: 260)
            if case .done = store.duplicatesStage {
                Text("\(Format.count(filteredGroups.count)) 组 · 可回收 \(Format.bytes(store.totalReclaimableBytes(filteredGroups)))")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if !marked.isEmpty {
                let entries = markedEntries
                let bytes = entries.reduce(UInt64(0)) { $0 + $1.size }
                Text("已标记 \(Format.count(entries.count)) 个 · \(Format.bytes(bytes))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent).monospacedDigit()
                Button {
                    store.requestDeletion(entries, mode: .trash)
                    marked.removeAll()
                } label: {
                    Label("移入废纸篓", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)

            }
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if store.duplicateStats.sampled > 0 {
                    Text("采样读取 \(Format.bytes(store.duplicateStats.sampled)) · 全量哈希 \(Format.bytes(store.duplicateStats.hashed)) · 缓存命中 \(Format.bytes(store.duplicateStats.cached)) · 硬链接组按物理块只计一次")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(filteredGroups) { group in
                    groupCard(group)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: "doc.on.doc.fill", tint: Palette.purple, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Format.count(group.files.count)) 个相同文件 · 每个 \(Format.bytes(group.fileSize))")
                        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                    Text("SHA-256 \(group.contentDigest.prefix(16))…").font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if group.containsHardlinks {
                    Text("含硬链接副本").font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.orange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Palette.orange.opacity(0.1), in: Capsule())
                        .help("组内存在共享同一物理数据的路径；删除硬链接副本不会立即释放空间")
                }
                Text("可回收 \(Format.bytes(group.reclaimableBytes))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent).monospacedDigit()
                Button("保留最新，标记其余") { markKeepingNewest(group) }
                    .font(.system(size: 11)).foregroundStyle(Palette.blue)
                    .buttonStyle(.link).fixedSize()
                    .help("按修改时间保留最新的一个，标记其余为待删除")
            }
            ForEach(group.files) { file in
                fileRow(group, file)
            }
        }
        .padding(12).panel()
    }

    private func fileRow(_ group: DuplicateGroup, _ file: FileEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.isHardlink ? "link" : "doc.fill")
                .font(.system(size: 10)).foregroundStyle(file.isHardlink ? Palette.orange : Palette.muted)
                .help(file.isHardlink ? "硬链接（link count \(file.linkCount ?? 1)）" : "普通文件")
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).help(file.path)
                Text(file.directory).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Format.date(file.modifiedAt)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            ToolButton(symbol: "magnifyingglass", label: "在访达中显示") { store.revealInFinder(file) }
            Button {
                if marked.contains(file.id) {
                    marked.remove(file.id)
                } else {
                    marked.insert(file.id)
                }
            } label: {
                Image(systemName: marked.contains(file.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(marked.contains(file.id) ? Palette.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(marked.contains(file.id) ? "取消标记" : "标记为待删除")
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(Color.primary.opacity(marked.contains(file.id) ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedEntry = file
        }
    }

    private func markKeepingNewest(_ group: DuplicateGroup) {
        guard let newest = group.files.max(by: { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }) else { return }
        for file in group.files where file.id != newest.id {
            marked.insert(file.id)
        }
    }
}
