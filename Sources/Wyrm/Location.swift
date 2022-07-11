//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class Location: Entity, Container {
    var name = ""
    var description = ""
    var size = Size.huge
    var capacity = Int.max
    var contents = [PhysicalEntity]()
    var exits = [Portal]()
    var tutorial: String?

    // FIXME: these should be symbols
    var domain: String?
    var surface: String?

    override func copyProperties(from other: Entity) {
        let other = other as! Location
        size = other.size
        capacity = other.capacity
        tutorial = other.tutorial
        domain = other.domain
        surface = other.surface
        // do not copy contents or exits
        super.copyProperties(from: other)
    }

    static let accessors = [
        "name": accessor(\Location.name),
        "description": accessor(\Location.description),
        "capacity": accessor(\Location.capacity),
        "contents": accessor(\Location.contents),
        "exits": accessor(\Location.exits),
        "tutorial": accessor(\Location.tutorial),
        "domain": accessor(\Location.domain),
        "surface": accessor(\Location.surface),
    ]

    override subscript(member: String) -> Value? {
        get { return Location.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Location.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }

    func findExit(_ direction: Direction) -> Portal? {
        return exits.first { $0.direction == direction }
    }
}
