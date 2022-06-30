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

let av = Avatar(withPrototype: nil)
print(Command.processInput(actor: av, input: "look star through telescope") ?? "")

#if false
let server = Server()
server.run()
#endif

let item = Item(withPrototype: nil)

let thing = Item(withPrototype: item)
thing.stackLimit = 10

let thing1 = Item(withPrototype: thing)
let thing2 = Item(withPrototype: thing)

print(Fixture.combine(thing1, into: thing2))
