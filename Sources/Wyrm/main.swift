//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

do {
    let db = try SQLiteConnection("/var/wyrm/wyrm.db")

    let stmt = try SQLiteStatement(
        db,
        "insert into accounts (username, password_key, salt) values (?, ?, ?)")

    for user in ["ann5", "cook4"] {
        try stmt.execute(user, "wakka_key", "hadhfsdf")
    }

    stmt.finalize()
    db.close()
} catch let e as SQLiteError {
    logger.error(e.message)
}

let server = Server(config: config)
server.run()
