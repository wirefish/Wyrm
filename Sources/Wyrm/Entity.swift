//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

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
