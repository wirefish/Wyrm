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

class Portal: Thing {
    var direction: Direction = .in
    var destination: Ref?
    var isCloseable = false
    var key: Item?
    var state = PortalState.open
    var exitMessage: String?
    weak var twin: Portal?

    override func copyProperties(from other: Entity) {
        let other = other as! Portal
        size = other.size
        isCloseable = other.isCloseable
        key = other.key
        state = other.state
        twin = other.twin
        super.copyProperties(from: other)
    }

    static let accessors = [
        "direction": Accessor(\Portal.direction),
        "destination": Accessor(\Portal.destination),
        "isCloseable": Accessor(\Portal.isCloseable),
        "key": Accessor(\Portal.key),
        "state": Accessor(\Portal.state),
        "exitMessage": Accessor(\Portal.exitMessage),
        "twin": Accessor(\Portal.twin),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    override func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return max(direction.match(tokens), super.match(tokens))
    }

    override func describeFully() -> String {
        if isObvious {
            let leads = pose?.replacingOccurrences(of: "$", with: String(describing: direction))
                ?? "leads \(direction)."
            return "\(describeBriefly([.capitalized, .indefinite])) \(leads) \(description ?? "")"
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

    actor.travel(via: portal)
}

// MARK: - travel-related extensions

extension Thing {
    @discardableResult
    func travel(via portal: Portal) -> Bool {
        let avatar = self as? Avatar

        guard let location = self.container as? Location else {
            avatar?.show("You don't have any way to leave this place.")
            return false
        }

        guard let destinationRef = portal.destination,
              let destination = World.instance.lookup(destinationRef, context: location.ref!)?
                .asEntity(Location.self) else {
            avatar?.show("A strange force prevents you from going that way.")
            return false
        }

        let entry = destination.findExit(portal.direction.opposite)
        guard triggerEvent("exitLocation", in: location, participants: [self, portal],
                           args: [self, location, portal], body: {
            avatar?.willExitLocation(via: portal)
            location.remove(self)
            let exitMessage = "\(self.describeBriefly([.capitalized, .indefinite])) heads \(portal.direction)."
            location.updateAll {
                $0.show(exitMessage)
                $0.removeNeighbor(self)
            }
        }) else {
            return false
        }

        triggerEvent("enterLocation", in: destination, participants: [self, entry!],
                     args: [self, destination, entry!]) {
            let enterMessage = "\(self.describeBriefly([.capitalized, .indefinite])) arrives from the \(entry!.direction)."
            destination.updateAll {
                $0.show(enterMessage)
                $0.updateNeighbor(self)
            }
            destination.insert(self)
            avatar?.didEnterLocation(via: entry!)
        }

        return true
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
