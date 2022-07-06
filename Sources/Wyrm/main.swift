//
//  main.swift
//  Wyrm
//

import Foundation
import Network
import Dispatch

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(config: config)
world.load()

// let server = Server(config: config)
// server.run()

if let server = Server(config: config) {
    server.run()
}
