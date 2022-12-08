//
//  main.swift
//  Wyrm
//

let config = try! Config(contentsOfFile: "config/config.toml")

let logger = Logger(level: .debug)  // FIXME:

let world = try! World(config: config)

/*
for i in 2...50 {
    let r = xpRequiredForLevel(i)
    let a = xpAwardedForLevel(i - 1)
    let q = questXPForLevel(i - 1)
    print(i, r, a, Double(r) / Double(a), q, Double(r) / Double(q))
}
*/

struct ItemFlags: OptionSet {
    let rawValue: UInt8

    static let hidden = ItemFlags(rawValue: 1 << 0)
    static let implied = ItemFlags(rawValue: 1 << 1)
}

extension ItemFlags {
    static let bound = ItemFlags(rawValue: 1 << 2)
}

print(MemoryLayout<ItemFlags>.size)
print(MemoryLayout<ItemFlags>.stride)

let f: ItemFlags = [.bound, .implied]
print(f.rawValue)

world.start()

if let server = GameServer(config) {
    server.run()
}
