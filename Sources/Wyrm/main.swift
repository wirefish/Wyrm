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

/*
let ip = ItemPrototype(ref: .absolute("__builtin__", "item"))
try! ip.set("stackLimit", to: .number(27))

let item = ip.instantiate()
print(ip, ip.stackLimit, item)

let p: Prototype = ItemPrototype(ref: .absolute("foo", "bar"), parent: ip)
try! p.set("something", to: .string("Bob"))
print(p.get("stackLimit")!)
print(p.get("something")!)

var q = Proto(ref: .absolute("foo", "bar"), proto: nil)
q.brief = NounPhrase("a slimy toad")
q.count = 1
print("brief is", q.brief, "and count is", q.count)
let c: Int? = q.count
print(c)
let d: String? = q.count
print(d)
if let x = q.count, let n = q.brief {
    print(x, n)
}
q[dynamicMember: "baz"] = 27
print(q.baz, q.proto, q.ref)
print(q.notFound)
 */

world.start()

if let server = GameServer(config) {
    server.run()
}
