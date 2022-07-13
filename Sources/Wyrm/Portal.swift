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
    var exitMessage: String?
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
        "direction": accessor(\Portal.direction),
        "is_closeable": accessor(\Portal.isCloseable),
        "lockable_with": accessor(\Portal.lockableWith),
        "state": accessor(\Portal.state),
        "exit_message": accessor(\Portal.exitMessage),
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

    override func describeFully() -> String {
        if isObvious {
            return "\(describeBriefly([.capitalized, .indefinite])) leads \(direction). \(super.describeFully())"
        } else {
            return super.describeFully()
        }
    }
}

// MARK: - go command

let goAliases = [
    ["n", "north"]: "go north",
    ["ne", "northeast"]: "go northeast",
    ["e", "east"]: "go east",
    ["se", "southeast"]: "go southeast",
    ["s", "south"]: "go south",
    ["sw", "southwest"]: "go southwest",
    ["w", "west"]: "go west",
    ["nw", "northwest"]: "go northwest",
    ["in", "enter"]: "go in",
    ["out", "exit"]: "go out",
    ["u", "up"]: "go up",
    ["d", "down"]: "go down",
]

let goHelp = """
Use the `go` command to move from one location to another. You can use a
direction, such as `go north`, or the name of an object, such as `go wooden
door`.

In addition, you can use shortcuts to move in common directions. For example,
you can type `n` or `north` instead of `go north`. Shortcuts are available for
all the compass directions as well as for `in`, `out`, `up`, and `down`.
"""

let goCommand = Command("go|head direction", aliases: goAliases, help: goHelp) {
    actor, verb, clauses in

    guard let location = actor.container as? Location else {
        actor.show("You cannot move right now.")
        return
    }

    guard case let .tokens(tokens) = clauses[0] else {
        actor.show("Where do you want to go?")
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

// MARK: - travel-related extensions

extension PhysicalEntity {
    func travel(to destination: Location, direction: Direction, via portal: Portal) {
        let avatar = self as? Avatar
        let entry = destination.findExit(direction.opposite)
        guard let location = self.container as? Location else {
            avatar?.show("You don't have any way to leave this place.")
            return
        }

        guard triggerEvent("exit_location", in: location, participants: [self, portal],
                           args: [self, location, portal], body: {
            avatar?.willExitLocation(via: portal)
            location.remove(self)
        }) else {
            return
        }

        triggerEvent("enter_location", in: destination, participants: [self, entry!],
                     args: [self, destination, entry!]) {
            destination.insert(self)
            avatar?.didEnterLocation(via: entry!)
        }
    }
}

extension Avatar {
    func willExitLocation(via portal: Portal) {
        // FIXME: add "along the path." or "through the door." - Portal can
        // define the prep to use.
        cancelActivity()
        cancelOffer()
        show(portal.exitMessage ?? "You head \(portal.direction).")
    }

    func didEnterLocation(via portal: Portal) {
        locationChanged()
    }
}
