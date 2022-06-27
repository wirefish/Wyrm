//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

let allFacetTypes: [Facet.Type] = [
    Container.self,
    Location.self,
    Portal.self,
    Viewable.self,
]

func findFacetType(forMember memberName: String) -> Facet.Type? {
    return allFacetTypes.first { $0.accessors.keys.contains(memberName) }
}

typealias EventHandler = (phase: EventPhase, event: String, method: CodeBlock)

// A reference to an entity may contain an explicit module name, in which case only that
// module is searched. Otherwise, the search uses the current module, any imported modules,
// and the default core module.
struct EntityRef: Equatable {
    let module: String?
    let name: String
}

class Entity: Observer, ValueDictionary, Equatable, CustomDebugStringConvertible {
    let prototype: Entity?
    let id = idIterator.next()!
    var facets = [Facet]()
    var handlers = [EventHandler]()

    static var idIterator = (1...).makeIterator()

    init(withPrototype prototype: Entity? = nil) {
        self.prototype = prototype
        if let p = self.prototype {
            facets = p.facets.compactMap { type(of: $0).isMutable ? $0.clone() : nil }
        }
    }

    func facet(_ t: Facet.Type) -> Facet? {
        facets.first { type(of: $0) == t } ?? prototype?.facet(t)
    }

    func requireFacet(forMember memberName: String) -> Facet? {
        guard let facetType = findFacetType(forMember: memberName) else {
            print("no facet type defines member \(memberName)")
            return nil
        }
        if let facet = facets.first(where: { type(of: $0) == facetType }) {
            return facet
        } else {
            let facet = prototype?.facet(facetType)?.clone() ?? facetType.init()
            facets.append(facet)
            return facet
        }
    }

    subscript(memberName: String) -> Value? {
        get {
            guard let facetType = findFacetType(forMember: memberName) else {
                return nil
            }
            return self.facet(facetType)?[memberName]
        }
        set {
            guard let facet = requireFacet(forMember: memberName) else {
                return
            }
            facet[memberName] = newValue
        }
    }

    static func == (lhs: Entity, rhs: Entity) -> Bool {
        return lhs === rhs
    }

    var debugDescription: String { "<Wyrm.Entity id=\(id) facets=\(facets)>" }
}
