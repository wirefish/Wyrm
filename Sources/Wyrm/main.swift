//
//  main.swift
//  Wyrm
//

import CoreFoundation

let world = World(rootPath: "/Users/craig/Projects/Wyrm/World")

let start = CFAbsoluteTimeGetCurrent()
world.load()
print(CFAbsoluteTimeGetCurrent() - start)

print(world.lookup(EntityRef(module: "isle_of_dawn", name: "officious_kobold"), context: nil)!)

let e = world.lookup(EntityRef(module: "isle_of_dawn", name: "wildflower_field"), context: nil)!
print(e["contents"])

let server = Server()
server.run()
