import SwiftUI
import FileCleanCore

/// 分类统计与筛选均基于同一次扫描；仅勾选当前可见文件参与批量操作。
struct LargeFilesView: View {
    @EnvironmentObject private var store: FileCleanStore
    @State private var selection = Set<String>()
    @State private var marked = Set<String>()
    @FocusState private var searchFocused: Bool

    private var filtered: [FileEntry] { store.filteredLargeFiles }
    private var markedFiles: [FileEntry] { filtered.filter { marked.contains($0.id) } }
    private var totalBytes: UInt64 { store.largeFiles.reduce(0) { $0 + $1.size } }
    private var busy: Bool { store.scanning || store.processingDeletion }

    var body: some View {
        VStack(spacing: 0) {
            if store.result != nil {
                categoryGrid
                filterBar
            }
            if store.scanning {
                EmptyState(symbol: "magnifyingglass", title: "正在分析文件", message: "扫描完成后，按文件种类汇总占用空间。")
            } else if store.result == nil {
                VStack(spacing: 16) {
                    EmptyState(symbol: "square.grid.2x2", title: "先看清空间都用在哪里", message: "扫描文件夹，按视频、文档、压缩包等种类查看大文件。")
                        .frame(maxHeight: 220)
                    Button("选择文件夹扫描…") { store.chooseScanDirectory() }
                        .buttonStyle(PrimaryButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 6) {
                    EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "没有匹配的文件", message: "试试其他分类、清空搜索，或降低大文件阈值。")
                        .frame(maxHeight: 210)
                    Button("显示全部大文件") {
                        store.largeFileCategory = nil
                        store.largeFileQuery = ""
                    }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
            selectionBar
        }
        .onChange(of: store.largeFileCategory) { _ in clearSelection() }
        .onChange(of: store.largeFileQuery) { _ in clearSelection() }
        .onChange(of: store.largeFileMiB) { _ in clearSelection() }
        .onChange(of: store.result?.finishedAt) { _ in clearSelection() }
        .onChange(of: store.largeFiles.map(\.id)) { ids in
            marked.formIntersection(Set(ids))
            selection.formIntersection(Set(ids))
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusFileCleanSearch)) { _ in
            if store.page == .large { searchFocused = true }
        }
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("按文件种类查看").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("仅归类展示，不移动文件").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                categoryCard(nil, count: store.largeFiles.count, bytes: totalBytes)
                ForEach(FileCategory.allCases) { category in
                    let summary = store.largeFileCategories.first { $0.category == category }
                    categoryCard(category, count: summary?.count ?? 0, bytes: summary?.bytes ?? 0)
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 18)
    }

    private func categoryCard(_ category: FileCategory?, count: Int, bytes: UInt64) -> some View {
        let selected = store.largeFileCategory == category
        let tint = category?.tint ?? Palette.accent
        return Button {
            store.largeFileCategory = category
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: category?.symbol ?? "square.grid.2x2")
                        .foregroundStyle(tint).font(.system(size: 11, weight: .medium))
                    Text(category?.title ?? "全部文件").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                }
                Text(Format.bytes(bytes)).font(.system(size: 17, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                HStack {
                    Text("\(Format.count(count)) 个文件").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.accent) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(11)
            .background(selected ? Palette.accent.opacity(0.075) : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.accent.opacity(0.65) : Palette.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category?.title ?? "全部文件")，\(count) 个文件，\(Format.bytes(bytes))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索名称或路径", text: $store.largeFileQuery)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("搜索大文件")
                if !store.largeFileQuery.isEmpty {
                    Button { store.largeFileQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("清空搜索")
                }
            }
            .font(.system(size: 11.5)).padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
            .frame(maxWidth: .infinity)
            Picker("大文件阈值", selection: $store.largeFileMiB) {
                ForEach([10, 50, 100, 500, 1024], id: \.self) { size in
                    Text(size == 1024 ? "≥ 1 GB" : "≥ \(size) MB").tag(size)
                }
            }.labelsHidden().frame(width: 112).help("大文件体积下限")
            Picker("排序方式", selection: $store.largeFileSort) {
                ForEach(LargeFileSort.allCases) { order in Text(order.title).tag(order) }
            }.labelsHidden().frame(width: 138)
        }
        .padding(.horizontal, 22).padding(.bottom, 12)
    }

    private var table: some View {
        Table(filtered, selection: $selection) {
            TableColumn("") { entry in
                Toggle("勾选 \(entry.name)", isOn: Binding(
                    get: { marked.contains(entry.id) },
                    set: { checked in if checked { marked.insert(entry.id) } else { marked.remove(entry.id) } }))
                    .labelsHidden().toggleStyle(.checkbox).disabled(busy)
            }.width(24)
            TableColumn("文件名称 / 位置") { entry in
                HStack(spacing: 10) {
                    SymbolBadge(symbol: entry.category.symbol, tint: selection.contains(entry.id) ? .white : entry.category.tint, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(entry.directory).font(.system(size: 10)).foregroundStyle(selection.contains(entry.id) ? Color.white.opacity(0.85) : .secondary).lineLimit(1).truncationMode(.middle)
                    }.help(entry.path)
                }.padding(.vertical, 5)
            }.width(min: 160)
            TableColumn("种类") { entry in
                Text(entry.category.title).font(.system(size: 10)).foregroundStyle(selection.contains(entry.id) ? .white : entry.category.tint)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(selection.contains(entry.id) ? Color.white.opacity(0.15) : entry.category.tint.opacity(0.08), in: Capsule())
            }.width(88)
            TableColumn("大小") { entry in
                Text(Format.bytes(entry.size)).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
            }.width(82)
            TableColumn("修改时间") { entry in
                Text(Format.date(entry.modifiedAt)).font(.system(size: 10)).monospacedDigit().foregroundStyle(selection.contains(entry.id) ? Color.white.opacity(0.85) : .secondary)
            }.width(92)
            TableColumn("") { entry in
                ToolButton(symbol: "ellipsis", label: "文件操作") {
                    store.selectedEntry = entry
                    store.showInspector = true
                }
            }.width(30)
        }
        .tableStyle(.inset)
        .contextMenu(forSelectionType: String.self) { paths in
            let entries = filtered.filter { paths.contains($0.id) }
            if !entries.isEmpty {
                Button("移入废纸篓…") { store.requestDeletion(entries) }.disabled(busy)
                Divider()
                Button("在访达中显示") { if let first = entries.first { store.revealInFinder(first) } }
                Button("复制路径") { if let first = entries.first { store.copyPath(first) } }
            }
        } primaryAction: { paths in
            if let path = paths.first { store.selectedEntry = filtered.first { $0.id == path } }
        }
        .onChange(of: selection) { paths in
            if let path = paths.first { store.selectedEntry = filtered.first { $0.id == path } }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(marked.count == filtered.count && !filtered.isEmpty ? "取消全选" : "全选当前结果") {
                    marked = marked.count == filtered.count ? [] : Set(filtered.map(\.id))
                }.buttonStyle(.plain).foregroundStyle(Palette.accent).disabled(filtered.isEmpty || busy)
                Text(marked.isEmpty
                     ? "\(Format.count(filtered.count)) 个文件"
                     : "已勾选 \(markedFiles.count) 个 · \(Format.bytes(markedFiles.reduce(0) { $0 + $1.size }))")
                    .foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                Button {
                    store.requestDeletion(markedFiles)
                } label: {
                    Label(store.processingDeletion ? "正在移入…" : "移入废纸篓…", systemImage: "trash")
                }.buttonStyle(PrimaryButtonStyle()).disabled(markedFiles.isEmpty || busy)
            }.font(.system(size: 11))
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward.circle")
                Text("可从废纸篓恢复；移入后不会立即释放磁盘空间。")
                Spacer()
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(Palette.surface)
        .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }

    private func clearSelection() {
        marked.removeAll()
        selection.removeAll()
        store.selectedEntry = nil
    }
}
