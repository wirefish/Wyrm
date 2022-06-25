import Foundation

let world = World(rootPath: "/Users/craig/Projects/Wyrm/World")

world.load()

let entity = Entity()

let f1 = entity.requireFacet(forMember: "brief")
let f2 = entity.requireFacet(forMember: "brief")
assert(f1 === f2)

let f3 = entity.requireFacet(forMember: "gargagr")
assert(f3 == nil)

let f4 = entity.requireFacet(forMember: "direction")
print(entity.facets)

f4!["size"] = .symbol("small")
print((f4 as! Portal).size)
