import Foundation

/// 应用更新检查：两类真实来源，不做猜测。
/// - Sparkle 自更新源（SUFeedURL，RSS appcast， enclosure 上的 sparkle:version 属性）；
/// - App Store 应用走 iTunes 公开 lookup 接口按 bundle ID 查询版本。
/// 其余应用（无源、非 App Store）如实标注"无更新源"，不冒充已最新。
public struct UpdateStatus: Identifiable, Hashable, Sendable {
    public enum State: Equatable, Hashable, Sendable {
        case upToDate
        case updateAvailable(latest: String)
        case unknown
        case noFeed
        case failed(String)
    }

    public let app: InstalledApp
    public let state: State
    public let source: String

    public var id: String { app.id }
}

public enum UpdateChecker {

    /// 点分版本号比较：逐段数值比较，非数值段按字符串比较；解析失败按字符串全序。
    public static func isVersion(_ left: String, olderThan right: String) -> Bool {
        let leftParts = left.split(separator: ".").map(String.init)
        let rightParts = right.split(separator: ".").map(String.init)
        let count = max(leftParts.count, rightParts.count)
        for index in 0..<count {
            let a = index < leftParts.count ? leftParts[index] : "0"
            let b = index < rightParts.count ? rightParts[index] : "0"
            if let aNumber = Int(a), let bNumber = Int(b) {
                if aNumber != bNumber { return aNumber < bNumber }
            } else if a != b {
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        }
        return false
    }

    /// 检查单个应用。仅显式触发时调用（涉及网络请求）。
    public static func check(app: InstalledApp) async -> UpdateStatus {
        if let feed = app.sparkleFeedURL, let url = URL(string: feed) {
            do {
                let latest = try await fetchSparkleLatest(feedURL: url)
                if let latest {
                    let state: UpdateStatus.State = isVersion(app.version, olderThan: latest)
                        ? .updateAvailable(latest: latest) : .upToDate
                    return UpdateStatus(app: app, state: state, source: "Sparkle 自更新源")
                }
                return UpdateStatus(app: app, state: .unknown, source: "Sparkle 自更新源（无条目）")
            } catch {
                return UpdateStatus(app: app, state: .failed(error.localizedDescription), source: "Sparkle 自更新源")
            }
        }
        if app.isFromAppStore {
            do {
                let latest = try await fetchAppStoreLatest(bundleID: app.bundleID)
                if let latest {
                    let state: UpdateStatus.State = isVersion(app.version, olderThan: latest)
                        ? .updateAvailable(latest: latest) : .upToDate
                    return UpdateStatus(app: app, state: state, source: "App Store")
                }
                return UpdateStatus(app: app, state: .unknown, source: "App Store（未收录）")
            } catch {
                return UpdateStatus(app: app, state: .failed(error.localizedDescription), source: "App Store")
            }
        }
        return UpdateStatus(app: app, state: .noFeed, source: "无更新源")
    }

    /// 解析 Sparkle appcast：取第一个 item 的 sparkle:shortVersionString（回退 sparkle:version）。
    static func fetchSparkleLatest(feedURL: URL) async throws -> String? {
        let (data, _) = try await URLSession.shared.data(from: feedURL)
        return parseAppcast(data)
    }

    /// 用 Foundation XMLParser 提取首个 item 的版本属性。
    public static func parseAppcast(_ data: Data) -> String? {
        let parser = AppcastParser()
        let delegate = ParserDelegateBridge(handler: parser)
        let xml = XMLParser(data: data)
        xml.delegate = delegate
        xml.parse()
        return parser.latestVersion
    }

    /// iTunes lookup：results[0].version；空结果返回 nil。
    static func fetchAppStoreLatest(bundleID: String) async throws -> String? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "entity", value: "macSoftware"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = document?["results"] as? [[String: Any]] ?? []
        return results.first?["version"] as? String
    }
}

/// XMLParser 的 delegate 需要 NSObject 传承，这里桥接到轻量处理器。
private final class ParserDelegateBridge: NSObject, XMLParserDelegate {
    let handler: AppcastParser

    init(handler: AppcastParser) {
        self.handler = handler
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "item" {
            handler.insideItem = true
        } else if handler.insideItem && elementName == "enclosure" {
            for key in ["sparkle:shortVersionString", "shortVersionString", "sparkle:version", "version"] {
                if let version = attributes[key], !version.isEmpty, handler.latestVersion == nil {
                    handler.latestVersion = version
                }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        if elementName == "item" { handler.insideItem = false }
    }
}

final class AppcastParser {
    var insideItem = false
    var latestVersion: String?
}
