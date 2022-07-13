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
        name = other.name
        description = other.description
        size = other.size
        capacity = other.capacity
        tutorial = other.tutorial
        domain = other.domain
        surface = other.surface
        contents = other.contents.map { $0.clone() }
        // do not copy exits
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

// MARK: - meditate command

class Meditation: Activity {
    func begin(_ avatar: Avatar) -> Double {
        avatar.show("You begin to meditate.")
        return 3.0
    }

    func cancel(_ avatar: Avatar) {
        avatar.show("Your meditation is interrupted.")
    }

    func finish(_ avatar: Avatar) {
        avatar.show("Your meditation is complete.")

        triggerEvent("meditate", in: avatar.location, participants: [avatar, avatar.location],
                     args: [avatar]) {
        }
    }
}

let meditateHelp = """
Use the `meditate` command to spend a few moments in quiet contemplation. The
effect of this action depends on your surroundings. Your meditation will be
interrupted if you move or are attacked.
"""

let meditateCommand = Command("meditate", help: meditateHelp) { actor, verb, clauses in
    actor.beginActivity(Meditation())
}
