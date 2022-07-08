//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

var state = AvatarState()
state.name = "Bob"
state.raceName = nil

state.changes["foo"] = .list([.string("hello"), .integer(123)])

let encoder = JSONEncoder()
let data = try! encoder.encode(state.changes)
print(String(data: data, encoding: .utf8)!)

if let server = GameServer(config) {
    server.run()
}
