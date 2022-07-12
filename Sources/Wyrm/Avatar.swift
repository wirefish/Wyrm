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

final class Avatar: PhysicalEntity {
    var level = 1

    // Equipped items.
    var equipped = [EquippedSlot:Item?]()

    // A mapping from identifiers of active quests to their current state.
    var activeQuests = [ValueRef:QuestState]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [ValueRef:Int]()

    var tutorialsSeen = Set<String>()

    // Current rank in all known skills.
    var skills = [ValueRef:Int]()

    // Pending offer, if any.
    var offer: Offer?

    // Current activity, if any.
    var activity: Activity?

    // Open WebSocket used to communicate with the client.
    var handler: WebSocketHandler?

    required init(withPrototype prototype: Entity?) {
        super.init(withPrototype: prototype)
    }

    var location: Location {
        get { container as! Location }
        set { container = newValue }
    }
}

// MARK: - as Codable

extension Avatar: Codable {
    enum CodingKeys: CodingKey {
        case level, location, equipped, activeQuests, completedQuests, skills
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
                location.contents.append(self)
                container = location
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
                    .string(actor.describeBriefly([.capitalized, .indefinite])),
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
        if tutorialsSeen.insert(key).inserted {
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
    let target = clauses[0], tool = clauses[1]

    if target == nil {
        if tool == nil {
            actor.describeLocation()
            return
        } else {
            // TODO:
        }
    } else {
        let location = actor.container as! Location
        guard let targetMatch = match(target!, against: location.contents, location.exits, where: {
            $0.isVisible(to: actor)
        }) else {
            actor.show("You don't see anything like that here.")
            return
        }

        // TODO: using tool

        for target in targetMatch {
            actor.show(target.describeFully())
        }
    }
}

// MARK: - talk command

let talkCommand = Command("talk to:target about:topic") { actor, verb, clauses in
    let candidates = actor.location.contents.filter {
        $0.canRespondTo(phase: .when, event: "talk")
    }

    var targets: [PhysicalEntity]
    if let targetPhrase = clauses[0] {
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
    let topic = clauses[1]?.joined(separator: " ") ?? ""

    triggerEvent("talk", in: actor.location, participants: [actor, target],
                 args: [actor, target, topic]) {
    }
}
