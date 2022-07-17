//
//  Location.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class Location: Entity {
    var name = ""
    var description = ""
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

    func insert(_ entity: PhysicalEntity) {
        contents.append(entity)
        entity.container = self
    }

    func remove(_ entity: PhysicalEntity) {
        if let index = contents.firstIndex(where: { $0 == entity }) {
            contents.remove(at: index)
            entity.container = nil
        }
    }

    func findExit(_ direction: Direction) -> Portal? {
        return exits.first { $0.direction == direction }
    }

    func addExit(_ portal: Portal) -> Bool {
        if findExit(portal.direction) == nil {
            exits.append(portal)
            // TODO: update the maps of any nearby players.
            return true
        } else {
            return false
        }
    }

    func removeExit(_ direction: Direction) -> Portal? {
        if let i = exits.firstIndex(where: { $0.direction == direction }) {
            return exits.remove(at: i)
        } else {
            return nil
        }
    }
}

// MARK: - meditate command

class Meditation: Activity {
    weak var avatar: Avatar?
    let duration: Double

    init(_ avatar: Avatar, duration: Double) {
        self.avatar = avatar
        self.duration = duration
    }

    func begin() {
        if let avatar = avatar {
            avatar.show("You begin to meditate.")
            avatar.sendMessage("startPlayerCast", .double(duration))
            World.schedule(delay: duration) { self.finish() }
        }
    }

    func cancel() {
        if let avatar = self.avatar {
            avatar.show("Your meditation is interrupted.")
            avatar.sendMessage("stopPlayerCast")
        }
        self.avatar = nil
    }

    func finish() {
        if let avatar = avatar {
            avatar.show("Your meditation is complete.")
            avatar.sendMessage("stopPlayerCast")
            triggerEvent("meditate", in: avatar.location, participants: [avatar, avatar.location],
                         args: [avatar]) {}
            avatar.activityFinished()
        }
    }
}

let meditateHelp = """
Use the `meditate` command to spend a few moments in quiet contemplation. The
effect of this action depends on your surroundings. Your meditation will be
interrupted if you move or are attacked.
"""

let meditateCommand = Command("meditate", help: meditateHelp) { actor, verb, clauses in
    actor.beginActivity(Meditation(actor, duration: 3.0))
}
