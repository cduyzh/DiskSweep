import Foundation
import UniformTypeIdentifiers

/// 只按文件名与系统类型声明分类，不读取内容，也不改变文件位置。
public enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case video, audio, image, document, archive, installer, development, virtualMachine, other

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .video: return "视频"
        case .audio: return "音频"
        case .image: return "图片与设计"
        case .document: return "文档"
        case .archive: return "压缩包"
        case .installer: return "安装包与镜像"
        case .development: return "开发与数据"
        case .virtualMachine: return "虚拟机"
        case .other: return "其他文件"
        }
    }
    public var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo.on.rectangle"
        case .document: return "doc.text"
        case .archive: return "doc.zipper"
        case .installer: return "shippingbox"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .virtualMachine: return "desktopcomputer"
        case .other: return "doc"
        }
    }

    public static func classify(_ url: URL) -> Self {
        let ext = url.pathExtension.lowercased()
        // Specialized formats take precedence over generic archive/data UTTypes.
        switch ext {
        case "vmdk", "vdi", "vhd", "vhdx", "qcow", "qcow2", "hdd", "pvm", "vmwarevm": return .virtualMachine
        case "dmg", "iso", "pkg", "mpkg", "ipsw", "img", "sparseimage", "sparsebundle", "exe", "msi", "deb", "rpm", "apk": return .installer
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "tgz", "tbz", "tbz2", "txz", "lz", "lzma": return .archive
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "mts", "m2ts", "flv", "wmv", "mpg", "mpeg": return .video
        case "mp3", "wav", "flac", "aiff", "aif", "m4a", "aac", "ogg", "opus", "alac", "caf": return .audio
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "avif", "svg", "raw", "dng", "cr2", "nef", "psd", "psb", "ai", "sketch", "fig", "afphoto", "afdesign": return .image
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "epub", "mobi", "rtf", "txt", "md", "csv", "odt", "ods", "odp": return .document
        case "db", "sqlite", "sqlite3", "sql", "json", "jsonl", "ndjson", "log", "parquet", "arrow", "h5", "hdf5", "safetensors", "gguf", "onnx", "pt", "pth", "ckpt", "npy", "npz", "swift", "js", "ts", "py", "go", "rs", "cpp", "c", "h", "java", "ipynb", "wasm": return .development
        default: break
        }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .sourceCode) || type.conforms(to: .database) { return .development }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) { return .document }
        if type.conforms(to: .archive) { return .archive }
        return .other
    }
}

public extension FileEntry {
    var category: FileCategory { FileCategory.classify(url) }
}

public struct FileCategorySummary: Identifiable, Sendable {
    public let category: FileCategory
    public let count: Int
    public let bytes: UInt64
    public var id: FileCategory { category }

    /// 保持固定分类顺序，让筛选时的位置稳定；未知扩展名也计入总量。
    public static func summarize(_ files: [FileEntry]) -> [Self] {
        var totals: [FileCategory: (count: Int, bytes: UInt64)] = [:]
        for file in files {
            let category = file.category
            let previous = totals[category, default: (0, 0)]
            totals[category] = (previous.count + 1, previous.bytes + file.size)
        }
        return FileCategory.allCases.compactMap { category in
            guard let total = totals[category] else { return nil }
            return Self(category: category, count: total.count, bytes: total.bytes)
        }
    }
}

public enum LargeFileSort: String, CaseIterable, Identifiable, Sendable {
    case size, modified, name
    public var id: Self { self }
    public var title: String {
        switch self {
        case .size: return "体积从大到小"
        case .modified: return "最近修改优先"
        case .name: return "名称 A → Z"
        }
    }

    public func filter(_ files: [FileEntry], category: FileCategory?, query: String) -> [FileEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter {
            (category == nil || $0.category == category) && (query.isEmpty || $0.path.localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            switch self {
            case .size:
                if lhs.size != rhs.size { return lhs.size > rhs.size }
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt { return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast) }
            case .name:
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return lhs.path < rhs.path
        }
    }
}
