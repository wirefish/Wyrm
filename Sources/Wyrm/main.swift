//
//  main.swift
//  Wyrm
//

import Foundation

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

let db = Database()
guard case .success = db.open("/var/wyrm/wyrm.db") else {
    fatalError("cannot open database")
}

if let accountID = db.authenticate(username: "ookie", password: "terrible_password") {
    print("authenticated \(accountID)")

    let avatar = Avatar(withPrototype: nil)

    let itemProto = Item(withPrototype: nil)
    itemProto.ref = .absolute("lib", "something")

    avatar.equipped[.head] = itemProto.clone()

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try! encoder.encode(avatar)
    print(String(data: data, encoding: .utf8)!)
}

db.close()

let server = Server(config: config)
server.run()
