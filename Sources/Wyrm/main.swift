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

if let server = TCPServer(port: config.server.port, handlerFactory: { GameHandler() }) {
    server.run()
}
