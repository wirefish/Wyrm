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

enum EventPhase {
    case allow, before, after
}

typealias EventHandler = (phase: EventPhase, event: String, method: CodeBlock)

// A reference to an entity may contain an explicit module name, in which case only that
// module is searched. Otherwise, the search uses the current module, any imported modules,
// and the default core module.
struct EntityRef {
    let module: String?
    let name: String
}

class Entity: ValueDictionary, CustomDebugStringConvertible {
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

    func findHandler(phase: EventPhase, event: String) -> CodeBlock? {
        // FIXME: This needs to match arguments against constraints as well.
        for handler in handlers {
            if handler.phase == phase && handler.event == event {
                return handler.method
            }
        }
        return nil
    }

    var debugDescription: String { "<Wyrm.Entity id=\(id) facets=\(facets)>" }
}
