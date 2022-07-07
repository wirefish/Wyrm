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

let base = URL(fileURLWithPath: "/Users/craig/Projects/Wyrm/client", isDirectory: true)
print(base)

let url = URL(fileURLWithPath: "index.md", relativeTo: base)
print(url)

let data = try! Data(contentsOf: url)
print(data)

if let server = TCPServer(port: config.server.port, handlerFactory: { GameHandler() }) {
    server.run()
}
