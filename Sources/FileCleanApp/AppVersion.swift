import Foundation

/// 版本与构建信息：以应用包内 Info.plist 为真值，不冒称远端状态。
struct AppVersion: Equatable {
    struct Record: Identifiable, Equatable {
        let version: String
        let build: String
        let date: String
        let title: String
        let summary: String
        let highlights: [String]
        let notes: [String]
        var id: String { "\(version)-\(build)" }
    }

    let version: String
    let build: String
    let buildDate: String
    let sourceRevision: String
    let sourceHash: String
    let runningPath: String
    let formallyInstalled: Bool
    let history: [Record]

    static let current = AppVersion()

    private init() {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        build = info["CFBundleVersion"] as? String ?? "0"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let raw = info["CDUYZHBuildDate"] as? String, let date = iso.date(from: raw) {
            buildDate = date.formatted(date: .abbreviated, time: .shortened)
        } else {
            buildDate = "本地开发构建"
        }
        sourceRevision = (info["CDUYZHSourceRevision"] as? String) ?? "unversioned"
        sourceHash = (info["CDUYZHSourceHash"] as? String) ?? ""
        runningPath = bundle.bundleURL.path
        formallyInstalled = bundle.bundleURL.path == "/Applications/cduyzhFileClean.app"
        history = AppVersion.loadHistory()
    }

    private static func loadHistory() -> [Record] {
        guard let url = Bundle.main.url(forResource: "ReleaseHistory", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = document["releases"] as? [[String: Any]] else { return [] }
        return releases.compactMap { release in
            guard let version = release["version"] as? String,
                  let build = release["build"] as? String,
                  let date = release["date"] as? String,
                  let title = release["title"] as? String,
                  let summary = release["summary"] as? String else { return nil }
            return Record(
                version: version, build: build, date: date, title: title, summary: summary,
                highlights: release["highlights"] as? [String] ?? [],
                notes: release["notes"] as? [String] ?? [])
        }
    }

    /// 来源摘要：Git 修订 + 源文件 SHA-256 前 12 位。
    var sourceSummary: String {
        let prefix = sourceHash.count > 12 ? String(sourceHash.prefix(12)) : sourceHash
        return "\(sourceRevision) · sha256 \(prefix)"
    }
}
