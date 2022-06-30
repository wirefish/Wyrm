//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

let server = Server(config: config)
// server.run()

let av = Avatar(withPrototype: nil)
let _ = Command.processInput(actor: av, input: "looK aT small Moon through telescope")

let entity = PhysicalEntity(withPrototype: nil)
entity.brief = NounPhrase("large red box[es]")

for input in ["red box", "re bo", "box", "green box", "large box", "large red box",
              "large red boxes", "large boxes", "box large",
              "a box", "99 boxes", "every box", "3 large red boxes", "3"] {
    let tokens = TokenSequence(input).map { String($0) }
    print("\(input): \(match(tokens, against: entity))")
}
