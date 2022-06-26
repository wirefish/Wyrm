//
//  Container.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

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
