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

let server = Server(config: config)
server.run()
