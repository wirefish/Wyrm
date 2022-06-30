//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

let server = Server(config: config)
// server.run()

let av = Avatar(withPrototype: nil)
let _ = Command.processInput(actor: av, input: "looK aT small Moon through telescope")
