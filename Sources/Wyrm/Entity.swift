//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

let notes = """

Compiling an entity creates code blocks for its init() and event handlers as well as a
code block to set the initial values of its members. Once all the entities are compiled,
the locations are instantiated. This recursively calls the member initializers for all
prototypes, if needed. In general an entity's member initializer is not run until the
entity is referenced.

Not that init() is really an initializer for new entities that use the entity as a prototype,
allowing them to customize member values. The default init() copies (or if mutable, clones)
the facets from this entity and declares it the prototype of the new entity. A custom init()
runs after that.

Only members explicitly present in an entity or its recursive chain of prototypes can be
accessed within an entity. In particular, init() cannot add new members.

"""

// FIXME: move this stuff around

class Viewable: Facet {
    var brief: NounPhrase?
    var description: String?
    var icon: String?
    var size = 22

    static let isMutable = false

    required init() {
    }

    func clone() -> Facet {
        let v = Viewable()
        v.brief = brief
        return v
    }

    static let accessors = [
        "brief": accessor(\Viewable.brief),
        "size": accessor(\Viewable.size)
    ]
}

class Container: Facet {
    var capacity = 1
    var contents = [Entity]()

    static let isMutable = true

    required init() {
    }
    
    func clone() -> Facet {
        let c = Container()
        c.capacity = capacity
        c.contents = []  // FIXME: map clone($0)
        return c
    }

    static let accessors = [
        "capacity": accessor(\Container.capacity),
        "contents": accessor(\Container.contents)
    ]
}

enum Size: CaseIterable, ValueRepresentable {
    case tiny, small, medium, large, huge

    static let names = Dictionary(uniqueKeysWithValues: Size.allCases.map {
        (String(describing: $0), $0)
    })

    init?(fromValue value: Value) {
        if let v = Size.enumCase(fromValue: value, names: Size.names) {
            self = v
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        return .symbol(String(describing: self))
    }
}

enum Direction: String {
    case north, northeast, east, southeast, south, southwest, west, northwest
    case up, down, `in`, out
}

typealias EntityPath = [String]

typealias EntityRef = (module: String?, name: String)

class Portal: Facet {
    var size = Size.large

    static let isMutable = true

    required init() {
    }

    func clone() -> Facet {
        let p = Portal()
        return p
    }

    static let accessors = [
        "size": accessor(\Portal.size),
    ]
}

// Note that an exit is not an entity or facet itself, but refers to a shared portal
// entity. What is a good syntax for this? Like an infix/ternary operator of some kind?
// Colon is free to use in this context, add a 'to' keyword and...
//   wooden_door: 'north [oneway] to other_room
// There would be an implied () because you'd always want to instantiate a new entity
// for the portal instead of sharing some global one. The matching exit would need to
// look for an existing exit opposite its direction and share the portal. We could go so
// far as creating opposite exits automagically, prevented by the oneway keyword.
struct Exit {
    let portal: Entity
    let direction: Direction
    let destination: EntityPath
}

class Location: Facet {
    var exits = [Exit]()

    static let isMutable = true

    required init() {
    }

    func clone() -> Facet {
        let f = Location()
        return f
    }

    static let exitAccessor = Accessor(
        get: { location in return .nil },
        set: { location, value in
        })

    static let accessors = [
        "exits": exitAccessor,
    ]
}

let allFacetTypes: [Facet.Type] = [
    Container.self,
    Portal.self,
    Viewable.self,
]

func findFacetType(forMember memberName: String) -> Facet.Type? {
    return allFacetTypes.first { $0.accessors.keys.contains(memberName) }
}

typealias EventAllower = (Entity, Event) -> Bool
typealias EventResponder = (Entity, Event) -> Void

class Entity: Observer {
    let prototype: Entity?
    var facets = [Facet]()

    init(withPrototype prototype: Entity? = nil) {
        self.prototype = prototype
    }

    func facet(_ t: Facet.Type) -> Facet? {
        return facets.first { type(of: $0) == t }
    }

    func requireFacet(forMember memberName: String) -> Facet? {
        if let facetType = findFacetType(forMember: memberName) {
            if let facet = self.facet(facetType) {
                return facet
            } else {
                let facet = facetType.init()
                facets.append(facet)
                return facet
            }
        } else {
            return nil
        }
    }
}
