import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

final class SQLitePersistence: ChatPersistence, @unchecked Sendable {
    private let db: OpaquePointer
    // All SQLite work runs on this dedicated serial queue — never on the main thread.
    private let queue = DispatchQueue(label: "apfel-chat.sqlite", qos: .userInitiated)

    init(path: String = SQLitePersistence.defaultPath()) throws {
        var dbPointer: OpaquePointer?
        // NOMUTEX: we serialise ourselves via `queue`; no need for SQLite's own mutex.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &dbPointer, flags, nil) == SQLITE_OK,
              let db = dbPointer else {
            let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            sqlite3_close(dbPointer)
            throw PersistenceError.openFailed(msg)
        }
        self.db = db
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA cache_size=-8000", nil, nil, nil)   // 8 MB page cache
        sqlite3_exec(db, "PRAGMA temp_store=MEMORY", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON", nil, nil, nil)
        try createTables()
        try rebuildSearchIndex()
    }

    /// Run a throwing block on the dedicated SQLite queue, bridging to async/await.
    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    deinit { sqlite3_close(db) }

    static func defaultPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = appSupport.appendingPathComponent("apfel-chat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chats.db").path
    }

    // MARK: - Schema

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            system_prompt TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            model_settings TEXT
        );
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp REAL NOT NULL,
            token_count INTEGER,
            duration_ms INTEGER,
            is_streaming INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_messages_conversation
            ON messages(conversation_id, timestamp);
        CREATE INDEX IF NOT EXISTS idx_conversations_updated_at
            ON conversations(updated_at DESC);
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            message_id UNINDEXED,
            conversation_id UNINDEXED,
            content,
            tokenize = 'unicode61'
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func rebuildSearchIndex() throws {
        try withTransaction {
            try self.execute("DELETE FROM messages_fts")
            try self.execute(
                "INSERT INTO messages_fts (message_id, conversation_id, content) SELECT id, conversation_id, content FROM messages"
            )
        }
    }

    // MARK: - SQLITE_TRANSIENT

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Conversations

    func createConversation(title: String) async throws -> Conversation {
        let conv = Conversation(title: title)
        return try await onQueue {
            let settingsJSON: String? = conv.modelSettings.flatMap {
                try? String(data: JSONEncoder().encode($0), encoding: .utf8)
            }
            try self.execute(
                "INSERT INTO conversations (id, title, system_prompt, created_at, updated_at, model_settings) VALUES (?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(conv.id), .text(conv.title), .textOrNull(conv.systemPrompt),
                    .real(conv.createdAt.timeIntervalSince1970),
                    .real(conv.updatedAt.timeIntervalSince1970),
                    .textOrNull(settingsJSON),
                ]
            )
            return conv
        }
    }

    func listConversations() async throws -> [Conversation] {
        try await onQueue {
            try self.query(
                "SELECT id, title, system_prompt, created_at, updated_at, model_settings FROM conversations ORDER BY updated_at DESC"
            ) { stmt in
                let settingsJSON = self.columnTextOrNil(stmt, 5)
                let settings: ModelSettings? = settingsJSON.flatMap {
                    try? JSONDecoder().decode(ModelSettings.self, from: $0.data(using: .utf8)!)
                }
                return Conversation(
                    id: String(cString: sqlite3_column_text(stmt, 0)),
                    title: String(cString: sqlite3_column_text(stmt, 1)),
                    systemPrompt: self.columnTextOrNil(stmt, 2),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    modelSettings: settings
                )
            }
        }
    }

    func deleteConversation(id: String) async throws {
        try await onQueue {
            try self.withTransaction {
                try self.execute("DELETE FROM messages_fts WHERE conversation_id = ?", bindings: [.text(id)])
                try self.execute("DELETE FROM messages WHERE conversation_id = ?", bindings: [.text(id)])
                try self.execute("DELETE FROM conversations WHERE id = ?", bindings: [.text(id)])
            }
        }
    }

    func updateConversation(_ conv: Conversation) async throws {
        try await onQueue {
            let settingsJSON: String? = conv.modelSettings.flatMap {
                try? String(data: JSONEncoder().encode($0), encoding: .utf8)
            }
            try self.execute(
                "UPDATE conversations SET title = ?, system_prompt = ?, updated_at = ?, model_settings = ? WHERE id = ?",
                bindings: [
                    .text(conv.title), .textOrNull(conv.systemPrompt),
                    .real(conv.updatedAt.timeIntervalSince1970),
                    .textOrNull(settingsJSON), .text(conv.id),
                ]
            )
        }
    }

    // MARK: - Messages

    func addMessage(_ msg: Message, to conversationId: String) async throws {
        try await onQueue {
            try self.withTransaction {
                try self.execute(
                    "INSERT INTO messages (id, conversation_id, role, content, timestamp, token_count, duration_ms, is_streaming) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    bindings: [
                        .text(msg.id), .text(conversationId), .text(msg.role.rawValue),
                        .text(msg.content), .real(msg.timestamp.timeIntervalSince1970),
                        .intOrNull(msg.tokenCount), .intOrNull(msg.durationMs),
                        .int(msg.isStreaming ? 1 : 0),
                    ]
                )
                try self.execute(
                    "INSERT INTO messages_fts (message_id, conversation_id, content) VALUES (?, ?, ?)",
                    bindings: [.text(msg.id), .text(conversationId), .text(msg.content)]
                )
                try self.execute(
                    "UPDATE conversations SET updated_at = ? WHERE id = ?",
                    bindings: [.real(Date().timeIntervalSince1970), .text(conversationId)]
                )
            }
        }
    }

    func messages(for conversationId: String) async throws -> [Message] {
        try await onQueue {
            try self.query(
                "SELECT id, conversation_id, role, content, timestamp, token_count, duration_ms, is_streaming FROM messages WHERE conversation_id = ? ORDER BY timestamp ASC",
                bindings: [.text(conversationId)]
            ) { stmt in
                Message(
                    id: String(cString: sqlite3_column_text(stmt, 0)),
                    conversationId: String(cString: sqlite3_column_text(stmt, 1)),
                    role: Role(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .user,
                    content: String(cString: sqlite3_column_text(stmt, 3)),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    tokenCount: self.columnIntOrNil(stmt, 5),
                    durationMs: self.columnIntOrNil(stmt, 6),
                    isStreaming: sqlite3_column_int(stmt, 7) != 0
                )
            }
        }
    }

    func updateMessage(_ msg: Message) async throws {
        try await onQueue {
            try self.withTransaction {
                try self.execute(
                    "UPDATE messages SET content = ?, token_count = ?, duration_ms = ?, is_streaming = ? WHERE id = ?",
                    bindings: [
                        .text(msg.content), .intOrNull(msg.tokenCount),
                        .intOrNull(msg.durationMs), .int(msg.isStreaming ? 1 : 0),
                        .text(msg.id),
                    ]
                )
                try self.execute(
                    "UPDATE messages_fts SET content = ? WHERE message_id = ?",
                    bindings: [.text(msg.content), .text(msg.id)]
                )
            }
        }
    }

    func searchConversations(query searchTerm: String) async throws -> [Conversation] {
        try await onQueue {
            let titlePattern = "%\(searchTerm)%"
            if let ftsQuery = self.ftsMatchQuery(from: searchTerm) {
                return try self.query(
                    """
                    SELECT * FROM (
                        SELECT id, title, system_prompt, created_at, updated_at, model_settings
                        FROM conversations
                        WHERE lower(title) LIKE lower(?)
                        UNION
                        SELECT c.id, c.title, c.system_prompt, c.created_at, c.updated_at, c.model_settings
                        FROM conversations c
                        JOIN (
                            SELECT DISTINCT conversation_id
                            FROM messages_fts
                            WHERE messages_fts MATCH ?
                            LIMIT 100
                        ) fts ON fts.conversation_id = c.id
                    )
                    ORDER BY updated_at DESC
                    LIMIT 100
                    """,
                    bindings: [.text(titlePattern), .text(ftsQuery)],
                    map: self.mapConversation
                )
            }

            return try self.query(
                """
                SELECT id, title, system_prompt, created_at, updated_at, model_settings
                FROM conversations
                WHERE lower(title) LIKE lower(?)
                ORDER BY updated_at DESC
                LIMIT 100
                """,
                bindings: [.text(titlePattern)],
                map: self.mapConversation
            )
        }
    }

    func search(query searchTerm: String) async throws -> [Message] {
        try await onQueue {
            try self.query(
                "SELECT id, conversation_id, role, content, timestamp, token_count, duration_ms, is_streaming FROM messages WHERE content LIKE ? ORDER BY timestamp DESC LIMIT 100",
                bindings: [.text("%\(searchTerm)%")]
            ) { stmt in
                Message(
                    id: String(cString: sqlite3_column_text(stmt, 0)),
                    conversationId: String(cString: sqlite3_column_text(stmt, 1)),
                    role: Role(rawValue: String(cString: sqlite3_column_text(stmt, 2))) ?? .user,
                    content: String(cString: sqlite3_column_text(stmt, 3)),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    tokenCount: self.columnIntOrNil(stmt, 5),
                    durationMs: self.columnIntOrNil(stmt, 6),
                    isStreaming: sqlite3_column_int(stmt, 7) != 0
                )
            }
        }
    }

    // MARK: - SQLite Helpers

    private enum Binding {
        case text(String)
        case textOrNull(String?)
        case int(Int)
        case intOrNull(Int?)
        case real(Double)
    }

    private func withTransaction(_ work: () throws -> Void) throws {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        do {
            try work()
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func execute(_ sql: String, bindings: [Binding] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, bindings: bindings)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(_ sql: String, bindings: [Binding] = [], map: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt: stmt!, bindings: bindings)
        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(map(stmt!))
        }
        return results
    }

    private func bind(stmt: OpaquePointer, bindings: [Binding]) {
        for (i, binding) in bindings.enumerated() {
            let idx = Int32(i + 1)
            switch binding {
            case .text(let v):
                sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .textOrNull(let v):
                if let v {
                    sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, idx)
                }
            case .int(let v):
                sqlite3_bind_int(stmt, idx, Int32(v))
            case .intOrNull(let v):
                if let v {
                    sqlite3_bind_int(stmt, idx, Int32(v))
                } else {
                    sqlite3_bind_null(stmt, idx)
                }
            case .real(let v):
                sqlite3_bind_double(stmt, idx, v)
            }
        }
    }

    private func columnTextOrNil(_ stmt: OpaquePointer, _ col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, col))
    }

    private func columnIntOrNil(_ stmt: OpaquePointer, _ col: Int32) -> Int? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(stmt, col))
    }

    private func mapConversation(_ stmt: OpaquePointer) -> Conversation {
        let settingsJSON = columnTextOrNil(stmt, 5)
        let settings: ModelSettings? = settingsJSON.flatMap {
            try? JSONDecoder().decode(ModelSettings.self, from: $0.data(using: .utf8)!)
        }
        return Conversation(
            id: String(cString: sqlite3_column_text(stmt, 0)),
            title: String(cString: sqlite3_column_text(stmt, 1)),
            systemPrompt: columnTextOrNil(stmt, 2),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            modelSettings: settings
        )
    }

    private func ftsMatchQuery(from query: String) -> String? {
        let tokens = query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(6)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " AND ")
    }
}

// MARK: - Errors

enum PersistenceError: LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Database open failed: \(msg)"
        case .queryFailed(let msg): return "Query failed: \(msg)"
        }
    }
}
