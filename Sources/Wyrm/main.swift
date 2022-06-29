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

print(world.lookup(.absolute("isle_of_dawn", "officious_kobold"), in: nil)!)

let e = world.lookup(.absolute("isle_of_dawn", "wildflower_field"), in: nil)!
if case let .list(contents) = (e.asEntity)?["contents"] {
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
