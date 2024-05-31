//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

world.start()

if let server = GameServer(config) {
    server.run()
}
