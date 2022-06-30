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
item.ref = .absolute("__BUILTIN__", "item")

let thing = item.extend()
thing.ref = .absolute("testy", "thing")
thing.stackLimit = 10
print("thing is \(thing)")

let thing1 = thing.extend()
let thing2 = thing.extend()

print("thing1 is \(thing1)")

print(Fixture.combine(thing1, into: thing2))

print("thing3 is \(thing1.copy())")

let fixture = Fixture(withPrototype: nil)
fixture.contents = [thing1, thing2]

let f1 = fixture.copy()
print(f1.contents)
