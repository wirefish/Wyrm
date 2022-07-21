//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "/Users/craig/Projects/Wyrm/config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

for i in 2...50 {
    let r = xpRequiredForLevel(i)
    let a = xpAwardedForLevel(i - 1)
    let q = questXPForLevel(i - 1)
    print(i, r, a, Double(r) / Double(a), q, Double(r) / Double(q))
}

world.start()

if let server = GameServer(config) {
    server.run()
}
