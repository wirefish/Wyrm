//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

let db = Database("/var/wyrm/wyrm.db")!

let stmt = Database.Statement(
    db: db,
    sql: "insert into accounts (username, password_key, salt) values (?, ?, ?)")!

for user in ["ann2", "cook2"] {
    stmt.execute(.string(user), .string("wakka_key"), .string("hadhfsdf"))
}

let server = Server(config: config)
server.run()
