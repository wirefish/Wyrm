//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = World(rootPath: config.world.rootPath)
world.load()

let db = Database()
guard case .success = db.open("/var/wyrm/wyrm.db") else {
    fatalError("cannot open database")
}

let result = db.createAccount(username: "wakka77", password: "terrible_password",
                              avatar: Avatar(withPrototype: nil))
switch result {
case let .failure(error):
    fatalError("cannot create account: \(error.message)")
case let .success(accountID):
    print("created account \(accountID)")
}

db.close()

let server = Server(config: config)
server.run()
