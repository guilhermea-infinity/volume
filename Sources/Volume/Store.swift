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
    var tag: String?
    var notes: String?
    /// Hand-sorted position in Up next.
    var sortIndex: Int = 0
    /// nil for hand-logged entries; "calendar" while the sync owns the row.
    var source: String?

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

    /// Silent classification: runs off the critical path, writes tags for
    /// completed tasks that have none. Never surfaces at entry time.
    func tagPending() {
        let pending = entries.filter { $0.kind == .task && $0.isDone && $0.tag == nil }
        guard !pending.isEmpty else { return }
        Task { @MainActor in
            for e in pending.prefix(50) {
                if let tag = await Tagger.tagAsync(e.title) {
                    self.setTag(tag.rawValue, for: e.id)
                }
            }
            self.load()
        }
    }

    /// Blocking variant for the headless renderer (lexicon backend only).
    func tagPendingSync() {
        for e in entries where e.kind == .task && e.isDone && e.tag == nil {
            if let tag = Tagger.tag(e.title) { setTag(tag.rawValue, for: e.id) }
        }
        load()
    }

    private func setTag(_ tag: String, for id: Int64) {
        run("UPDATE entries SET tag = ? WHERE id = ?") { st in
            sqlite3_bind_text(st, 1, tag, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(st, 2, id)
        }
    }

    func clearAllTags() {
        run("UPDATE entries SET tag = NULL")
        load()
    }

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
        exec("ALTER TABLE entries ADD COLUMN tag TEXT")
        exec("ALTER TABLE entries ADD COLUMN notes TEXT")
        exec("ALTER TABLE entries ADD COLUMN sort_index INTEGER")
        // Rows from before hand-sorting keep the order they already had.
        exec("UPDATE entries SET sort_index = id WHERE sort_index IS NULL")
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
        let sql = "SELECT id, kind, title, estimate_min, actual_min, created_at, completed_at, tag, source, notes, sort_index FROM entries ORDER BY created_at ASC, id ASC"
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
                let tag = sqlite3_column_text(st, 7).map { String(cString: $0) }
                let source = sqlite3_column_text(st, 8).map { String(cString: $0) }
                let notes = sqlite3_column_text(st, 9).map { String(cString: $0) }
                let sortIndex = sqlite3_column_type(st, 10) == SQLITE_NULL
                    ? Int(id) : Int(sqlite3_column_int64(st, 10))
                out.append(Entry(id: id, kind: kind, title: title, estimateMin: est,
                                 actualMin: act, createdAt: created, completedAt: completed,
                                 tag: tag, notes: notes, sortIndex: sortIndex, source: source))
            }
            sqlite3_finalize(st)
        }
        if out != entries { entries = out }
    }

    // MARK: - Mutations

    func addPlanned(title: String, estimateMin: Int) {
        // New work lands at the bottom of Up next, under whatever you've sorted.
        run("""
            INSERT INTO entries(kind, title, estimate_min, created_at, sort_index)
            VALUES('task', ?, ?, ?, (SELECT COALESCE(MAX(sort_index), -1) + 1 FROM entries))
            """) { st in
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
        tagPending()
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
        tagPending()
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

    /// Edit a logged entry. A calendar-sourced row becomes "calendar-edited":
    /// the next sync no longer replaces it, and its external_id keeps that sync
    /// from inserting the original back alongside it.
    func update(_ id: Int64, title: String, estimateMin: Int?, actualMin: Int?, completedAt: Date?) {
        run("""
            UPDATE entries
               SET title = ?, estimate_min = ?, actual_min = ?, completed_at = ?, tag = NULL,
                   source = CASE WHEN source = 'calendar' THEN 'calendar-edited' ELSE source END
             WHERE id = ?
            """) { st in
            sqlite3_bind_text(st, 1, title, -1, SQLITE_TRANSIENT)
            bindInt(st, 2, estimateMin)
            bindInt(st, 3, actualMin)
            bindInt64(st, 4, completedAt.map { Int64($0.timeIntervalSince1970) })
            sqlite3_bind_int64(st, 5, id)
        }
        load()
        tagPending()
    }

    private func bindInt(_ st: OpaquePointer, _ idx: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int(st, idx, Int32(value)) } else { sqlite3_bind_null(st, idx) }
    }

    private func bindInt64(_ st: OpaquePointer, _ idx: Int32, _ value: Int64?) {
        if let value { sqlite3_bind_int64(st, idx, value) } else { sqlite3_bind_null(st, idx) }
    }

    /// Writes the hand-sorted order of Up next, top to bottom.
    func reorder(_ ids: [Int64]) {
        exec("BEGIN")
        for (i, id) in ids.enumerated() {
            run("UPDATE entries SET sort_index = ? WHERE id = ?") { st in
                sqlite3_bind_int(st, 1, Int32(i))
                sqlite3_bind_int64(st, 2, id)
            }
        }
        exec("COMMIT")
        load()
    }

    /// Notes save as you type, so nothing here reloads the whole table — the
    /// row is patched in place and the open editor keeps its cursor.
    func setNotes(_ notes: String, for id: Int64) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        run("UPDATE entries SET notes = ? WHERE id = ?") { st in
            if let value { sqlite3_bind_text(st, 1, value, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_null(st, 1) }
            sqlite3_bind_int64(st, 2, id)
        }
        if let i = entries.firstIndex(where: { $0.id == id }), entries[i].notes != value {
            entries[i].notes = value
        }
    }

    func delete(_ id: Int64) {
        run("DELETE FROM entries WHERE id = ?") { st in
            sqlite3_bind_int64(st, 1, id)
        }
        load()
    }
}
