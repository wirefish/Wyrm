//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import AppKit

// Possible directions of movement.
enum Direction: Int, ValueRepresentableEnum {
    case north = 0, northeast, east, southeast, south, southwest, west, northwest
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

    var offset: (Int, Int, Int) {
        switch self {
        case .north: return (0, -1, 0)
        case .northeast: return (1, -1, 0)
        case .east: return (1, 0, 0)
        case .southeast: return (1, 1, 0)
        case .south: return (0, 1, 0)
        case .southwest: return (-1, 1, 0)
        case .west: return (-1, 0, 0)
        case .northwest: return (-1, -1, 0)
        case .up: return (0, 0, 1)
        case .down: return (0, 0, -1)
        case .in: return (0, 0, 0)
        case .out: return (0, 0, 0)
        }
    }

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

// Note that an exit is not an entity or facet itself, but refers to a shared portal
// entity.
struct Exit {
    let portal: Portal
    let direction: Direction
    let destination: ValueRef

    init(portal: Portal, direction: Direction, destination: ValueRef) {
        self.portal = portal
        self.direction = direction
        self.destination = destination
    }
}

class Location: Entity, Container {
    var name = ""
    var description = ""
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

    func findExit(_ direction: Direction) -> Exit? {
        return exits.first { $0.direction == direction }
    }
}

extension PhysicalEntity {

    func travel(to destination: Location, direction: Direction, via portal: Portal) {
        let entry = destination.findExit(direction.opposite)
        guard let location = self.container as? Location else {
            // Feedback?
            return
        }

        guard triggerEvent("exit_location", in: location, participants: [self, portal],
                           args: [self, location, portal], body: {
            location.remove(self)
        }) else {
            return
        }

        triggerEvent("enter_location", in: location, participants: [self, entry!.portal],
                     args: [self, location, entry!.portal]) {
            location.insert(self)
            // describeLocation()
        }
    }
}
