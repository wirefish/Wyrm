//
//  main.swift
//  Wyrm
//

import CoreFoundation
import Foundation

let world = World(rootPath: "/Users/craig/Projects/Wyrm/World")

let start = CFAbsoluteTimeGetCurrent()
world.load()
print(String(format: "loaded world in %.4f seconds", CFAbsoluteTimeGetCurrent() - start))

print(world.lookup(EntityRef(module: "isle_of_dawn", name: "officious_kobold"), context: nil)!)

let e = world.lookup(EntityRef(module: "isle_of_dawn", name: "wildflower_field"), context: nil)!
if case let .list(contents) = e["contents"] {
    print(contents)
    let k = contents.values.first!
    print(k)

    if case let .entity(e) = k, let item = e as? Item {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try! encoder.encode(item)
        print(String(data: data, encoding: .utf8)!)
    }
}

let server = Server()
server.run()
