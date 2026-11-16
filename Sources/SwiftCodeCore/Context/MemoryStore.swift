import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Summary metadata for a stored session.
public struct PersistedSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let workspacePath: String
    public let mode: AgentMode
    public let createdAt: Date
    public let updatedAt: Date
}

/// Knowledge note stored in SQLite FTS5 and Markdown files under `~/.swiftcode/memory/`.
public struct MemoryNote: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let updatedAt: Date
}

/// Persistent cross-session SQLite/FTS5 & Markdown store (FR-3.3).
public actor MemoryStore {
    private let databaseURL: URL
    private let memoryDirectoryURL: URL
    #if canImport(SQLite3)
    private let connection: SQLiteConnection?
    private var db: OpaquePointer? { connection?.handle }
    #endif

    public init(
        databaseURL: URL = ConfigurationStore().stateDatabaseURL,
        memoryDirectoryURL: URL = ConfigurationStore().memoryDirectoryURL
    ) throws {
        self.databaseURL = databaseURL
        self.memoryDirectoryURL = memoryDirectoryURL
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoryDirectoryURL, withIntermediateDirectories: true)
        #if canImport(SQLite3)
        var handle: OpaquePointer?
        if sqlite3_open(databaseURL.path, &handle) == SQLITE_OK, let handle {
            self.connection = SQLiteConnection(handle: handle)
            try Self.initializeSchema(on: handle)
        } else {
            self.connection = nil
        }
        #endif
    }

    public func saveSession(id: UUID, title: String, workspaceRoot: URL, mode: AgentMode, events: [AgentEvent]) throws {
        let now = Date().timeIntervalSince1970
        let payload = try JSONEncoder().encode(events)
        let json = String(data: payload, encoding: .utf8) ?? "[]"
        #if canImport(SQLite3)
        if let db {
            try executePrepared(db: db, sql: """
            INSERT INTO sessions (id, title, workspace_path, mode, created_at, updated_at, events_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                mode = excluded.mode,
                updated_at = excluded.updated_at,
                events_json = excluded.events_json;
            """, bindings: [id.uuidString, title, workspaceRoot.path, mode.rawValue, now, now, json])
            return
        }
        #endif
        let fallbackURL = memoryDirectoryURL.appendingPathComponent("session-\(id.uuidString).json")
        try payload.write(to: fallbackURL, options: .atomic)
    }

    public func loadSessionEvents(id: UUID) throws -> [AgentEvent] {
        #if canImport(SQLite3)
        if let db {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT events_json FROM sessions WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                return []
            }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                let data = Data(String(cString: cStr).utf8)
                return (try? JSONDecoder().decode([AgentEvent].self, from: data)) ?? []
            }
            return []
        }
        #endif
        let fallbackURL = memoryDirectoryURL.appendingPathComponent("session-\(id.uuidString).json")
        guard let data = try? Data(contentsOf: fallbackURL) else { return [] }
        return (try? JSONDecoder().decode([AgentEvent].self, from: data)) ?? []
    }

    public func listSessions(limit: Int = 50) -> [PersistedSessionSummary] {
        #if canImport(SQLite3)
        if let db {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT id, title, workspace_path, mode, created_at, updated_at FROM sessions ORDER BY updated_at DESC LIMIT ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var rows: [PersistedSessionSummary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(stmt, 0),
                      let uuid = UUID(uuidString: String(cString: idC)),
                      let titleC = sqlite3_column_text(stmt, 1),
                      let pathC = sqlite3_column_text(stmt, 2),
                      let modeC = sqlite3_column_text(stmt, 3) else { continue }
                rows.append(PersistedSessionSummary(
                    id: uuid,
                    title: String(cString: titleC),
                    workspacePath: String(cString: pathC),
                    mode: AgentMode(rawValue: String(cString: modeC)) ?? .plan,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                ))
            }
            return rows
        }
        #endif
        return []
    }

    /// Saves a persistent Markdown knowledge note and indexes it in SQLite FTS5.
    public func saveMemoryNote(id: String, title: String, body: String) throws {
        let sanitizedID = id.replacingOccurrences(of: "/", with: "-")
        let mdURL = memoryDirectoryURL.appendingPathComponent("\(sanitizedID).md")
        try "# \(title)\n\n\(body)\n".write(to: mdURL, atomically: true, encoding: .utf8)
        #if canImport(SQLite3)
        if let db {
            try executePrepared(db: db, sql: "DELETE FROM memory_fts WHERE note_id = ?;", bindings: [sanitizedID])
            try executePrepared(db: db, sql: "INSERT INTO memory_fts (note_id, title, body) VALUES (?, ?, ?);", bindings: [sanitizedID, title, body])
        }
        #endif
    }

    /// Searches long-term knowledge notes via SQLite FTS5 BM25 (or Markdown scan fallback).
    public func searchMemoryNotes(query: String, limit: Int = 10) -> [MemoryNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        #if canImport(SQLite3)
        if let db {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "SELECT note_id, title, body FROM memory_fts WHERE memory_fts MATCH ? ORDER BY bm25(memory_fts) LIMIT ?;"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let sanitized = trimmed.replacingOccurrences(of: "\"", with: "")
                sqlite3_bind_text(stmt, 1, sanitized, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_int(stmt, 2, Int32(limit))
                var results: [MemoryNote] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idC = sqlite3_column_text(stmt, 0),
                       let titleC = sqlite3_column_text(stmt, 1),
                       let bodyC = sqlite3_column_text(stmt, 2) {
                        results.append(MemoryNote(
                            id: String(cString: idC),
                            title: String(cString: titleC),
                            body: String(cString: bodyC),
                            updatedAt: Date()
                        ))
                    }
                }
                if !results.isEmpty { return results }
            }
        }
        #endif
        return searchMarkdownFiles(query: trimmed, limit: limit)
    }

    /// Exports a session's event history as human-readable Markdown (`/export`).
    public func exportSessionMarkdown(id: UUID) throws -> String {
        let events = try loadSessionEvents(id: id)
        var lines = ["# SwiftCode Session \(id.uuidString)", ""]
        for event in events {
            switch event.kind {
            case .userMessage(let text):
                lines.append("## User\n\n\(text)\n")
            case .assistantTokenDelta(let delta):
                lines.append(delta)
            case .toolExecutionCompleted(_, let name, let output, let ms):
                lines.append("\n> Tool `\(name)` (\(ms)ms)\n```\n\(output.content.prefix(1000))\n```\n")
            case .checkpointCreated(let hash, let label):
                lines.append("- Checkpoint `\(hash.prefix(8))`: \(label)")
            default:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    private func searchMarkdownFiles(query: String, limit: Int) -> [MemoryNote] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: memoryDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        var scored: [(Int, MemoryNote)] = []
        for url in urls where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            let score = terms.reduce(0) { $0 + (lower.contains($1) ? 1 : 0) }
            if score > 0 {
                let firstLine = text.split(separator: "\n").first.map(String.init) ?? url.deletingPathExtension().lastPathComponent
                let title = firstLine.replacingOccurrences(of: "# ", with: "")
                scored.append((score, MemoryNote(id: url.deletingPathExtension().lastPathComponent, title: title, body: text, updatedAt: Date())))
            }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    #if canImport(SQLite3)
    private static func initializeSchema(on db: OpaquePointer?) throws {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            mode TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            events_json TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(note_id, title, body);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func executePrepared(db: OpaquePointer, sql: String, bindings: [Any]) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (idx, value) in bindings.enumerated() {
            let pos = Int32(idx + 1)
            if let str = value as? String {
                sqlite3_bind_text(stmt, pos, str, -1, transient)
            } else if let dbl = value as? Double {
                sqlite3_bind_double(stmt, pos, dbl)
            } else if let intVal = value as? Int {
                sqlite3_bind_int64(stmt, pos, Int64(intVal))
            }
        }
        sqlite3_step(stmt)
    }
    #endif
}

#if canImport(SQLite3)
private final class SQLiteConnection {
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}
#endif
