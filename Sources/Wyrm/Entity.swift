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

let allFacetTypes: [Facet.Type] = [
    Container.self,
    Location.self,
    Portal.self,
    Viewable.self,
]

func findFacetType(forMember memberName: String) -> Facet.Type? {
    return allFacetTypes.first { $0.accessors.keys.contains(memberName) }
}

typealias EventAllower = (Entity, Event) -> Bool
typealias EventResponder = (Entity, Event) -> Void

// A reference to an entity may contain an explicit module name, in which case only that
// module is searched. Otherwise, the search uses the current module, any imported modules,
// and the default core module.
typealias EntityRef = (module: String?, name: String)

class Entity: Observer {
    let prototype: Entity?
    var facets = [Facet]()

    init(withPrototype prototype: Entity? = nil) {
        self.prototype = prototype
        if let p = self.prototype {
            facets = p.facets.map { type(of: $0).isMutable ? $0.clone() : $0 }
        }
    }

    func facet(_ t: Facet.Type) -> Facet? {
        facets.first { type(of: $0) == t } ?? prototype?.facet(t)
    }

    func requireFacet(forMember memberName: String) -> Facet? {
        guard let facetType = findFacetType(forMember: memberName) else {
            return nil
        }
        if let facet = self.facet(facetType) {
            return facet
        } else {
            let facet = prototype?.facet(facetType)?.clone() ?? facetType.init()
            facets.append(facet)
            return facet
        }
    }
}
