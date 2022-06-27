//
//  main.swift
//  Wyrm
//

import NIOCore
import TOMLDecoder

let world = World(rootPath: "/Users/craig/Projects/Wyrm/World")
world.load()

let entity = world.lookup(EntityRef(module: "isle_of_dawn", name: "spirit_warden"),
                          context: nil)!

let handler = entity.findHandler(phase: .after, event: "enter_location")!

let context: [ValueDictionary] = [world.modules["isle_of_dawn"]!, entity]

let result = try! world.exec(handler, args: [.entity(entity), .nil, .nil, .nil], context: context)
print(result)
print(entity["pose"] ?? nil)

