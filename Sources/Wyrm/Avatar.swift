//
//  Avatar.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import Foundation

enum EquippedSlot: String, CodingKeyRepresentable, Hashable, Encodable {
    // Weapons and tools.
    case mainHand, offHand

    // Clothing.
    case head, torso, hands, waist, legs, feet

    // Accessories.
    case ears, neck, wrists, leftFinger, rightFinger
}

final class Race: ValueDictionaryObject, CustomDebugStringConvertible {
    let ref: ValueRef
    var brief: NounPhrase?

    init(ref: ValueRef) {
        self.ref = ref
    }

    static let accessors = [
        "brief": accessor(\Race.brief),
    ]

    func describeBriefly(_ format: Text.Format) -> String {
        // FIXME:
        return brief!.format(format)
    }

    var debugDescription: String { "<Race \(ref)>" }
}

final class Inventory: Container {
    required init(withPrototype proto: Entity? = nil) {
        super.init(withPrototype: proto)
        self.capacity = 5
    }
}

final class Avatar: PhysicalEntity {
    var level = 1
    var race: Race?

    var inventory = Inventory()

    // Equipped items.
    var equipped = [EquippedSlot:Item?]()

    // A mapping from identifiers of active quests to their current state.
    var activeQuests = [ValueRef:QuestState]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [ValueRef:Int]()

    // Current rank in all known skills.
    var skills = [ValueRef:Int]()

    // Tutorials.
    var tutorialsOn = true
    var tutorialsSeen = Set<String>()

    // Pending offer, if any.
    var offer: Offer?

    // Current activity, if any.
    var activity: Activity?

    // Cached copy of last map displayed to the player.
    var map: Map?

    // Open WebSocket used to communicate with the client.
    var handler: WebSocketHandler?

    private static let accessors = [
        "race": accessor(\Avatar.race),
        "location": accessor(\Avatar.location),
    ]

    override subscript(member: String) -> Value? {
        get { Self.accessors[member]?.get(self) ?? super[member] }
        set {
            if Self.accessors[member]?.set(self, newValue!) == nil {
                super[member] = newValue
            }
        }
    }
}

// MARK: - as Codable

extension Avatar: Codable {
    enum CodingKeys: CodingKey {
        case level, location, race, equipped, activeQuests, completedQuests, skills
    }

    convenience init(from decoder: Decoder) throws {
        self.init(withPrototype: World.instance.avatarPrototype)
        copyProperties(from: World.instance.avatarPrototype)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(Int.self, forKey: .level)

        let locationRef = try container.decode(ValueRef.self, forKey: .location)
        if let loc = World.instance.lookup(locationRef, context: nil)?.asEntity(Location.self) {
            self.container = loc
        } else {
            logger.warning("cannot find location \(locationRef), using start location")
            self.container = World.instance.startLocation
        }

        if let raceRef = try container.decodeIfPresent(ValueRef.self, forKey: .race) {
            if case let .race(race) = World.instance.lookup(raceRef, context: nil) {
                self.race = race
            } else {
                logger.warning("cannot find race \(raceRef)")
            }
        } else {
            logger.warning("avatar has no race")
        }

        // TODO: other fields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(location.ref, forKey: .location)
        try container.encode(equipped, forKey: .equipped)
        try container.encode(activeQuests, forKey: .activeQuests)
        try container.encode(completedQuests, forKey: .completedQuests)
        try container.encode(skills, forKey: .skills)
    }
}

// MARK: - as WebSocketDelegate

extension Avatar: WebSocketDelegate {
    func onOpen(_ handler: WebSocketHandler) {
        let reconnecting = self.handler != nil
        self.handler = handler

        if reconnecting {
            sendMessage("showNotice", .string("Welcome back!"))
            // TODO: update entire UI state.
            locationChanged()
        } else {
            // FIXME: figure out a portal to use.
            // TODO: update entire UI state.

            triggerEvent("enter_location", in: location, participants: [self],
                         args: [self, location]) {
                location.insert(self)
                locationChanged()
            }
        }
    }

    func onClose(_ handler: WebSocketHandler) {
        self.handler = nil
    }

    func onReceiveMessage(_ handler: WebSocketHandler, _ message: String) {
        Command.processInput(actor: self, input: message)
    }
}

// MARK: - sending client messages

extension Avatar {

    func sendMessage(_ fn: String, _ args: ClientValue...) {
        if let handler = handler {
            let encoder = JSONEncoder()
            let data = try! encoder.encode(ClientCall(fn: fn, args: args))
            handler.sendTextMessage(String(data: data, encoding: .utf8)!)
        }
    }

    func show(_ message: String) {
        sendMessage("showText", .string(message))
    }

    func showNotice(_ message: String) {
        sendMessage("showNotice", .string(message))
    }

    func showSay(_ actor: PhysicalEntity, _ verb: String, _ message: String, _ isChat: Bool) {
        sendMessage("showSay",
                    .string(actor.describeBriefly([.capitalized, .definite])),
                    .string(verb),
                    .string(message),
                    .boolean(isChat))
    }

    func locationChanged() {
        describeLocation()
        showMap()
        if let tutorial = location.tutorial, let key = location.ref?.description {
            showTutorial(key, tutorial)
        }
    }

    func showTutorial(_ key: String, _ message: String) {
        if tutorialsOn && tutorialsSeen.insert(key).inserted {
            sendMessage("showTutorial", .string(message))
        }
    }

    func describeLocation() {
        let exits = location.exits.filter{ $0.isObvious(to: self) }
            .map { ClientValue.string(String(describing: $0.direction)) }

        let contents = location.contents.filter { $0 != self && $0.isObvious(to: self) }
            .map {
                ClientValue.list([.integer($0.id),
                                  .string($0.describeBriefly([.capitalized, .indefinite])),
                                  .string($0.describePose())])
            }

        sendMessage("showLocation",
                    .string(location.name),
                    .string(location.description),
                    .list(exits),
                    .list(contents))
    }

    func showLinks(_ heading: String, _ prefix: String, _ links: [String]) {
        sendMessage("showLinks", .string(heading), .string(prefix),
                    .list(links.map { ClientValue.string($0) }))
    }

    func showList(_ heading: String, _ items: [String]) {
        sendMessage("showList", .string(heading), .list(items.map { ClientValue.string($0) }))
    }
}

// MARK: - look command

let lookCommand = Command("look at:target with|using|through:tool") { actor, verb, clauses in
    if case let .tokens(target) = clauses[0] {
        let location = actor.container as! Location
        guard let targetMatch = match(target, against: location.contents, location.exits, where: {
            $0.isVisible(to: actor)
        }) else {
            actor.show("You don't see anything like that here.")
            return
        }

        // TODO: using tool

        for target in targetMatch {
            actor.show(target.describeFully())
        }
    } else {
        if case let .tokens(tool) = clauses[1] {
            // TODO:
        } else {
            actor.describeLocation()
        }
    }
}

// MARK: - talk command

let talkCommand = Command("talk to:target about:topic") { actor, verb, clauses in
    let candidates = actor.location.contents.filter {
        $0.canRespondTo(phase: .when, event: "talk")
    }

    var targets: [PhysicalEntity]
    if case let .tokens(targetPhrase) = clauses[0] {
        guard let match = match(targetPhrase, against: candidates) else {
            actor.show("There's nobody like that here to talk to.")
            return
        }
        targets = match.matches
    } else {
        guard candidates.count > 0 else {
            actor.show("There's nobody here to talk to.")
            return
        }
        targets = candidates
    }

    guard targets.count == 1 else {
        let names = targets.map { $0.describeBriefly([.definite]) }
        actor.show("Do you want to talk to \(names.conjunction(using: "or"))?")
        return
    }

    let target = targets.first!
    let topic = clauses[1].asString

    triggerEvent("talk", in: actor.location, participants: [actor, target],
                 args: [actor, target, topic]) {
    }
}

// MARK: - tutorial command

let tutorialHelp = """
Use the `tutorial` command to control how you see tutorial messages associated
with locations or actions. Tutorials are used to introduce new players to game
concepts and commands.

The command can be used in several ways:

- Type `tutorial` to see the tutorial associated with the current location, if any.

- Type `tutorial off` to disable display of tutorials.

- Type `tutorial on` to re-enable display of tutorials. Tutorials are on by default.

- Type `tutorial reset` to clear your memory of the tutorials you've already
seen. You will see them again the next time you encounter them.
"""

let tutorialCommand = Command("tutorial 1:subcommand", help: tutorialHelp) { actor, verb, clauses in
    if case let .string(subcommand) = clauses[0] {
        switch subcommand {
        case "on":
            actor.tutorialsOn = true
            actor.show("Tutorials are enabled.")
        case "off":
            actor.tutorialsOn = false
            actor.show("Tutorials are disabled.")
        case "reset":
            actor.tutorialsSeen = []
            actor.show("Tutorials have been reset.")
        default:
            actor.show("Unrecognized subcommand \"\(subcommand)\".")
        }
    } else {
        if let tutorial = actor.location.tutorial {
            actor.sendMessage("showTutorial", .string(tutorial))
        } else {
            actor.show("There is no tutorial associated with this location.")
        }
    }
}
