import Foundation
import SQLite3

/// 重复检测的持久化哈希缓存：以 (路径, 大小, 修改时间纳秒) 为键
/// 存储采样与全量摘要。文件未变化时直接复用上次结果，二次扫描近乎零读盘。
/// 缓存本身只是性能优化：未命中或损坏时回退为重新计算，不影响结果正确性。
public final class HashCache: @unchecked Sendable {
    public struct Stats: Sendable {
        public var hits = 0
        public var misses = 0
        public var stored = 0
    }

    private var database: OpaquePointer?
    private let lock = NSLock()
    public private(set) var stats = Stats()

    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cduyzhFileClean", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("hash-cache.sqlite3")
    }

    public init(url: URL = HashCache.defaultURL()) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "无法打开"
            if let handle { sqlite3_close(handle) }
            throw NSError(domain: "HashCache", code: 1, userInfo: [NSLocalizedDescriptionKey: "哈希缓存打开失败：\(message)"])
        }
        database = handle
        // WAL + normal 同步：性能优先，缓存损坏可接受（自动回退重算）。
        _ = exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        try execThrowing("""
        CREATE TABLE IF NOT EXISTS entries (
            path TEXT PRIMARY KEY,
            size INTEGER NOT NULL,
            mtime_ns INTEGER NOT NULL,
            sample TEXT,
            full TEXT,
            updated_at REAL NOT NULL
        );
        """)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private func exec(_ sql: String) -> Bool {
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }
        return sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK
    }

    private func execThrowing(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorPointer) }
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "SQL 执行失败"
            throw NSError(domain: "HashCache", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// 查询未变化文件的全量摘要；键不匹配（文件已改动）返回 nil。
    public func fullDigest(path: String, size: UInt64, mtimeNs: Int64) -> String? {
        lock.lock(); defer { lock.unlock() }
        let sql = "SELECT full FROM entries WHERE path = ?1 AND size = ?2 AND mtime_ns = ?3 AND full IS NOT NULL;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, Int64(bitPattern: size))
        sqlite3_bind_int64(statement, 3, mtimeNs)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            stats.misses += 1
            return nil
        }
        stats.hits += 1
        return String(cString: text)
    }

    /// 写入（UPSERT）一条摘要记录。
    public func save(path: String, size: UInt64, mtimeNs: Int64, sample: String?, full: String?) {
        lock.lock(); defer { lock.unlock() }
        let sql = """
        INSERT INTO entries (path, size, mtime_ns, sample, full, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        ON CONFLICT(path) DO UPDATE SET
            size = excluded.size, mtime_ns = excluded.mtime_ns,
            sample = excluded.sample, full = excluded.full, updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, Int64(bitPattern: size))
        sqlite3_bind_int64(statement, 3, mtimeNs)
        sqlite3_bind_text(statement, 4, sample, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, full, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        stats.stored += 1
    }

    /// 删除不再存在于给定键集合中的记录，控制缓存体积。
    /// 返回删除的行数；为避免超长 SQL，按路径前缀分批构建临时表比对。
    @discardableResult
    public func prune(validKeys: [(path: String, size: UInt64, mtimeNs: Int64)]) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard exec("CREATE TEMP TABLE IF NOT EXISTS live (path TEXT PRIMARY KEY, size INTEGER, mtime_ns INTEGER);"),
              exec("DELETE FROM live;") else { return 0 }
        var insert: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO live (path, size, mtime_ns) VALUES (?1, ?2, ?3);", -1, &insert, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(insert) }
        sqlite3_exec(database, "BEGIN IMMEDIATE;", nil, nil, nil)
        for key in validKeys {
            sqlite3_reset(insert)
            sqlite3_bind_text(insert, 1, key.path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(insert, 2, Int64(bitPattern: key.size))
            sqlite3_bind_int64(insert, 3, key.mtimeNs)
            sqlite3_step(insert)
        }
        sqlite3_exec(database, "COMMIT;", nil, nil, nil)
        var deleted: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM entries WHERE path NOT IN (SELECT path FROM live);", -1, &deleted, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(deleted) }
        guard sqlite3_step(deleted) == SQLITE_DONE else { return 0 }
        return Int(sqlite3_changes(database))
    }

    public func entryCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM entries;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        defer { sqlite3_finalize(statement) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// 文件修改时间折算为自 1970 起的纳秒，作为缓存键的一部分。
    public static func mtimeNanoseconds(_ date: Date?) -> Int64 {
        guard let date else { return 0 }
        let seconds = date.timeIntervalSince1970
        return Int64(seconds) * 1_000_000_000 + Int64((seconds.truncatingRemainder(dividingBy: 1)) * 1_000_000_000)
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
