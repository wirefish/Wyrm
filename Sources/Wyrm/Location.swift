//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// Possible directions of movement.
enum Direction: String {
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
}

// A reference to an entity may contain an explicit module name, in which case only that
// module is searched. Otherwise, the search uses the current module, any imported modules,
// and the default core module.
typealias EntityRef = (module: String?, name: String)

class Portal: Facet {
    static let isMutable = true

    required init() {
    }

    func clone() -> Facet {
        let p = Portal()
        return p
    }

    static let accessors = [String:Accessor]()
}

// Note that an exit is not an entity or facet itself, but refers to a shared portal
// entity.
struct Exit: ValueRepresentable {
    let portal: Entity
    let direction: Direction
    let destination: EntityRef

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

    static let isMutable = true

    required init() {
    }

    func clone() -> Facet {
        let f = Location()
        f.exits = exits
        return f
    }

    static let exitAccessor = Accessor(
        get: { location in return .nil },
        set: { location, value in
        })

    static let accessors = [
        "exits": accessor(\Location.exits),
    ]
}
