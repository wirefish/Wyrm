//
//  Database.swift
//  Wyrm
//

import SQLite3

class Database {
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
