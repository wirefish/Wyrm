//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

if let server = GameServer(config) {
    server.run()
}

