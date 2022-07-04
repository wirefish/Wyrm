//
//  SQLite.swift
//  Wyrm
//

import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteError: Error {
    let message: String

    init(_ fn: String, _ err: String) {
        message = "\(fn): \(err)"
    }

    init(_ fn: String, _ status: Int32) {
        message = "\(fn): \(String(utf8String: sqlite3_errstr(status)) ?? "unknown error")"
    }
}

struct SQLiteConnection {
    let db: OpaquePointer!

    init(_ path: String) throws {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
        guard status == SQLITE_OK else {
            throw SQLiteError("sqlite3_open_v2", status)
        }
        self.db = db
    }

    func close() {
        sqlite3_close(db)
    }
}

struct SQLiteStatement {
    let stmt: OpaquePointer!

    init(_ conn: SQLiteConnection, _ sql: String) throws {
        var stmt: OpaquePointer?
        let status = sqlite3_prepare_v2(conn.db, sql, -1, &stmt, nil)
        guard status == SQLITE_OK else {
            throw SQLiteError("sqlite3_prepare_v2", status)
        }
        self.stmt = stmt
    }

    func finalize() {
        sqlite3_finalize(stmt)
    }

    func execute(_ bindings: Any...) throws {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        try bind(bindings)
        let status = sqlite3_step(stmt)
        guard status == SQLITE_DONE else {
            throw SQLiteError("sqlite3_step", status)
        }
    }

    func query(_ bindings: Any...) throws -> SQLiteRowSequence {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        try bind(bindings)
        return SQLiteRowSequence(stmt: self)
    }

    private func bind(_ bindings: [Any]) throws {
        let paramCount = sqlite3_bind_parameter_count(stmt)
        guard paramCount == bindings.count else {
            throw SQLiteError(
                "bind",
                "wrong number of bindings: got \(bindings.count), expected \(paramCount)")
        }
        for (index, binding) in bindings.enumerated() {
            if let i = binding as? Int {
                if sqlite3_bind_int64(stmt, Int32(index + 1), Int64(i)) != SQLITE_OK {
                    throw SQLiteError("bind", "cannot bind int64 at index \(index)")
                }
            } else if let s = binding as? String {
                if sqlite3_bind_text(stmt, Int32(index + 1), s, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                    throw SQLiteError("bind", "cannot bind string at index \(index)")
                }
            } else {
                throw SQLiteError("bind", "cannot bind value of unsupported type")
            }
        }
    }
}

struct SQLiteRowSequence: Sequence, IteratorProtocol {
    let stmt: SQLiteStatement

    mutating func next() -> SQLiteRow? {
        let status = sqlite3_step(stmt.stmt)
        if status == SQLITE_ROW {
            return SQLiteRow(stmt: stmt)
        } else {
            return nil
        }
    }
}

struct SQLiteRow {
    let stmt: SQLiteStatement

    func getInt(column: Int) -> Int? {
        return Int(sqlite3_column_int64(stmt.stmt, Int32(column)))
    }

    func getString(column: Int) -> String? {
        guard let ptr = UnsafeRawPointer(sqlite3_column_text(stmt.stmt, Int32(column))) else {
            return nil
        }
        let uptr = ptr.bindMemory(to: CChar.self, capacity: 0)
        return String(validatingUTF8: uptr)
    }
}
