//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(config: config)
world.load()

if let server = GameServer(config) {
    server.run()
}
