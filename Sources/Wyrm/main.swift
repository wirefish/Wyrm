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

let data = Data(repeating: 33, count: 1024)
print(data.startIndex)
data.withUnsafeBytes { print($0) }

var r = data[1...]
print(r.startIndex)
r.withUnsafeBytes { print($0) }
print(data[0], r[1])
r[1] = 128
print(data[0], r[1])
r.withUnsafeBytes { print($0) }

if let server = HTTPServer(port: config.server.port, handlerFactory: { GameHandler() }) {
    server.run()
}
