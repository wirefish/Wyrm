//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// Possible directions of movement.
enum Direction: Equatable, CaseIterable, ValueRepresentable {
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

    static let names = Dictionary(uniqueKeysWithValues: Direction.allCases.map {
        (String(describing: $0), $0)
    })

    init?(fromValue value: Value) {
        if let v = Direction.enumCase(fromValue: value, names: Direction.names) {
            self = v
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        return .symbol(String(describing: self))
    }
}

class Portal: Facet {
    static let isMutable = true

    var isCloseable = false
    var isOpen = true

    required init() {
    }

    func clone() -> Facet {
        let p = Portal()
        return p
    }

    static let accessors = [
        "is_closeable": accessor(\Portal.isCloseable),
        "is_open": accessor(\Portal.isOpen),
    ]
}

// Note that an exit is not an entity or facet itself, but refers to a shared portal
// entity.
struct Exit: ValueRepresentable, Equatable {
    let portal: Entity
    let direction: Direction
    let destination: EntityRef

    init(portal: Entity, direction: Direction, destination: EntityRef) {
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

class Location: Facet {
    var exits = [Exit]()
    var tutorial: String?

    // FIXME: these should be symbols
    var domain: String?
    var surface: String?

    static let isMutable = true

    required init() {
    }

    func clone() -> Facet {
        let f = Location()
        f.exits = exits
        return f
    }

    static let accessors = [
        "exits": accessor(\Location.exits),
        "tutorial": accessor(\Location.tutorial),
        "domain": accessor(\Location.domain),
        "surface": accessor(\Location.surface),
    ]
}
