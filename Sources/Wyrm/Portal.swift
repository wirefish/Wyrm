//
//  Portal.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

// MARK: - Portal

enum PortalState: ValueRepresentableEnum {
    case open, closed, locked

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

class Portal: PhysicalEntity {
    var direction: Direction = .in
    var destination: ValueRef?
    var isCloseable = false
    var lockableWith: Item?
    var state = PortalState.open
    weak var twin: Portal?

    override func copyProperties(from other: Entity) {
        let other = other as! Portal
        size = other.size
        isCloseable = other.isCloseable
        lockableWith = other.lockableWith
        state = other.state
        twin = other.twin
        super.copyProperties(from: other)
    }

    static let accessors = [
        "is_closeable": accessor(\Portal.isCloseable),
        "lockable_with": accessor(\Portal.lockableWith),
        "state": accessor(\Portal.state),
        "twin": accessor(\Portal.twin),
    ]

    override subscript(member: String) -> Value? {
        get { return Portal.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Portal.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }

    override func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return max(direction.match(tokens), super.match(tokens))
    }
}

// MARK: - goCommand

let goCommand = Command("go direction") {
    actor, verb, clauses in
    print(actor, clauses)

    guard let location = actor.container as? Location else {
        actor.show("You cannot move right now.")
        return
    }

    guard case let .phrase(_, tokens) = clauses[0] else {
        return
    }

    guard let matches = match(tokens, against: location.exits) else {
        actor.show("You don't see any exit matching that description.")
        return
    }

    guard matches.count == 1 else {
        let dirs = matches.map { String(describing: $0.direction) }
        actor.show("Do you want to go \(dirs.conjunction(using: "or"))?")
        return
    }
    let portal = matches.first!

    guard let destinationRef = portal.destination,
          let destination = World.instance.lookup(destinationRef, context: location.ref!)?
            .asEntity(Location.self) else {
        actor.show("A strange force prevents you from going that way.")
        return
    }

    actor.travel(to: destination, direction: portal.direction, via: portal)
}

// MARK: - PhysicalEntity+travel

extension PhysicalEntity {
    func travel(to destination: Location, direction: Direction, via portal: Portal) {
        let avatar = self as? Avatar
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

        triggerEvent("enter_location", in: destination, participants: [self, entry!],
                     args: [self, destination, entry!]) {
            destination.insert(self)
            avatar?.locationChanged()
        }
    }
}
