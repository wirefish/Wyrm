//
//  Database.swift
//  Wyrm
//

import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class Database {

    enum Binding {
        case integer(Int)
        case string(String)
    }

    class Statement {
        var stmt: OpaquePointer!

        init?(db: Database, sql: String) {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db.db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            self.stmt = stmt
        }

        deinit {
            sqlite3_finalize(stmt)
        }

        func execute(_ bindings: Binding...) {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bind(bindings)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("cannot execute statement")
            }
        }

        private func bind(_ bindings: [Binding]) {
            guard sqlite3_bind_parameter_count(stmt) == bindings.count else {
                logger.error("binding count does not match")
                return
            }
            for (index, binding) in bindings.enumerated() {
                switch binding {
                case let .integer(i):
                    if sqlite3_bind_int64(stmt, Int32(index + 1), Int64(i)) != SQLITE_OK {
                        logger.error("cannot bind int64 at index \(index)")
                    }
                case let .string(s):
                    if sqlite3_bind_text(stmt, Int32(index + 1), s, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                        logger.error("cannot bind string at index \(index)")
                    }
                }
            }
        }
    }

    let db: OpaquePointer!

    init?(_ path: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            return nil
        }
        self.db = db
    }

    deinit {
        sqlite3_close(db)
    }
}
