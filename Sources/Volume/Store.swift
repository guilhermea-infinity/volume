import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum Kind: String {
    case task
    case call
}

struct Entry: Identifiable, Hashable {
    let id: Int64
    var kind: Kind
    var title: String
    var estimateMin: Int?
    var actualMin: Int?
    var createdAt: Date
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    private var db: OpaquePointer?

    init() {
        open()
        load()
        // Pick up external writes (calendar sync) even when idle
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() { load() }

    private func open() {
        let path: String
        if let override = ProcessInfo.processInfo.environment["VOLUME_DB"] {
            path = override
        } else {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Volume", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("volume.db").path
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        exec("PRAGMA journal_mode=WAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL DEFAULT 'task',
          title TEXT NOT NULL,
          estimate_min INTEGER,
          actual_min INTEGER,
          created_at INTEGER NOT NULL,
          completed_at INTEGER,
          source TEXT,
          external_id TEXT
        );
        """)
        // Migrations for DBs created before calendar sync (errors are no-ops when the column exists)
        exec("ALTER TABLE entries ADD COLUMN source TEXT")
        exec("ALTER TABLE entries ADD COLUMN external_id TEXT")
        exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_external ON entries(external_id) WHERE external_id IS NOT NULL")
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func run(_ sql: String, bind: (OpaquePointer) -> Void = { _ in }) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let st = stmt else { return }
        bind(st)
        sqlite3_step(st)
        sqlite3_finalize(st)
    }

    private func load() {
        var out: [Entry] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id, kind, title, estimate_min, actual_min, created_at, completed_at FROM entries ORDER BY created_at ASC, id ASC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let st = stmt {
            while sqlite3_step(st) == SQLITE_ROW {
                let id = sqlite3_column_int64(st, 0)
                let kind = sqlite3_column_text(st, 1).map { Kind(rawValue: String(cString: $0)) ?? .task } ?? .task
                let title = sqlite3_column_text(st, 2).map { String(cString: $0) } ?? ""
                let est = sqlite3_column_type(st, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 3))
                let act = sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 4))
                let created = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(st, 5)))
                let completed = sqlite3_column_type(st, 6) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(st, 6)))
                out.append(Entry(id: id, kind: kind, title: title, estimateMin: est,
                                 actualMin: act, createdAt: created, completedAt: completed))
            }
            sqlite3_finalize(st)
        }
        if out != entries { entries = out }
    }

    // MARK: - Mutations

    func addPlanned(title: String, estimateMin: Int) {
        run("INSERT INTO entries(kind, title, estimate_min, created_at) VALUES('task', ?, ?, ?)") { st in
            sqlite3_bind_text(st, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 2, Int32(estimateMin))
            sqlite3_bind_int64(st, 3, Int64(Date.now.timeIntervalSince1970))
        }
        load()
    }

    func complete(_ id: Int64, actualMin: Int) {
        run("UPDATE entries SET actual_min = ?, completed_at = ? WHERE id = ?") { st in
            sqlite3_bind_int(st, 1, Int32(actualMin))
            sqlite3_bind_int64(st, 2, Int64(Date.now.timeIntervalSince1970))
            sqlite3_bind_int64(st, 3, id)
        }
        load()
    }

    func addRetro(title: String, estimateMin: Int, actualMin: Int, at date: Date) {
        let ts = Int64(date.timeIntervalSince1970)
        run("INSERT INTO entries(kind, title, estimate_min, actual_min, created_at, completed_at) VALUES('task', ?, ?, ?, ?, ?)") { st in
            sqlite3_bind_text(st, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 2, Int32(estimateMin))
            sqlite3_bind_int(st, 3, Int32(actualMin))
            sqlite3_bind_int64(st, 4, ts)
            sqlite3_bind_int64(st, 5, ts)
        }
        load()
    }

    func addCall(title: String, minutes: Int, at date: Date) {
        let ts = Int64(date.timeIntervalSince1970)
        run("INSERT INTO entries(kind, title, actual_min, created_at, completed_at) VALUES('call', ?, ?, ?, ?)") { st in
            sqlite3_bind_text(st, 1, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(st, 2, Int32(minutes))
            sqlite3_bind_int64(st, 3, ts)
            sqlite3_bind_int64(st, 4, ts)
        }
        load()
    }

    struct CalendarCall {
        let externalId: String
        let title: String
        let minutes: Int
        let endedAt: Date
    }

    /// Reconciles calendar-sourced calls inside the window: the calendar is
    /// the source of truth there, manual entries are never touched.
    func syncCalendarCalls(_ items: [CalendarCall], windowStart: Date, windowEnd: Date) {
        run("DELETE FROM entries WHERE source = 'calendar' AND completed_at >= ? AND completed_at <= ?") { st in
            sqlite3_bind_int64(st, 1, Int64(windowStart.timeIntervalSince1970))
            sqlite3_bind_int64(st, 2, Int64(windowEnd.timeIntervalSince1970))
        }
        for item in items {
            run("INSERT OR IGNORE INTO entries(kind, title, actual_min, created_at, completed_at, source, external_id) VALUES('call', ?, ?, ?, ?, 'calendar', ?)") { st in
                sqlite3_bind_text(st, 1, item.title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(st, 2, Int32(item.minutes))
                sqlite3_bind_int64(st, 3, Int64(item.endedAt.timeIntervalSince1970))
                sqlite3_bind_int64(st, 4, Int64(item.endedAt.timeIntervalSince1970))
                sqlite3_bind_text(st, 5, item.externalId, -1, SQLITE_TRANSIENT)
            }
        }
        load()
    }

    func delete(_ id: Int64) {
        run("DELETE FROM entries WHERE id = ?") { st in
            sqlite3_bind_int64(st, 1, id)
        }
        load()
    }
}
