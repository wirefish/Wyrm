//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// Possible directions of movement.
enum Direction: ValueRepresentableEnum {
    case north, northeast, east, southeast, south, southwest, west, northwest
    case up, down, `in`, out

    var opposite: Direction {
        switch self {
        case .north: return .south
        case .northeast: return .southwest
        case .east: return .west
        case .southeast: return .northwest
        case .south: return .north
        case .southwest: return .northeast
        case .west: return .east
        case .northwest: return .southeast
        case .up: return .down
        case .down: return .up
        case .in: return .out
        case .out: return .in
        }
    }

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

// Note that an exit is not an entity or facet itself, but refers to a shared portal
// entity.
struct Exit: ValueRepresentable {
    let portal: Portal
    let direction: Direction
    let destination: ValueRef

    init(portal: Portal, direction: Direction, destination: ValueRef) {
        self.portal = portal
        self.direction = direction
        self.destination = destination
    }

    init?(fromValue value: Value) {
        guard case let .exit(exit) = value else {
            return nil
        }
        self = exit
    }

    func toValue() -> Value {
        return .exit(self)
    }
}

class Location: Entity, Container {
    var size = Size.huge
    var capacity = Int.max
    var contents = [PhysicalEntity]()
    var exits = [Exit]()
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
}
