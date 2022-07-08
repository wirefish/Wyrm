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

final class Avatar: PhysicalEntity, Codable {
    var level = 1

    // Current location.
    weak var location: Location!

    // Equipped items.
    var equipped = [EquippedSlot:Item?]()

    // A mapping from identifiers of active quests to their current state.
    var activeQuests = [ValueRef:QuestState]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [ValueRef:Int]()

    // Current rank in all known skills.
    var skills = [ValueRef:Int]()

    // Open WebSocket used to communicate with the client.
    var handler: WebSocketHandler?

    enum CodingKeys: CodingKey {
        case level, location, equipped, activeQuests, completedQuests, skills
    }

    required init(withPrototype prototype: Entity?) {
        super.init(withPrototype: prototype)
    }

    init(from decoder: Decoder) throws {
        super.init(withPrototype: World.instance.avatarPrototype)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(Int.self, forKey: .level)

        let locationRef = try container.decode(ValueRef.self, forKey: .location)
        if let loc = World.instance.lookup(locationRef, in: nil)?.asEntity(Location.self) {
            location = loc
        } else {
            logger.warning("cannot find location \(locationRef), using start location")
            location = World.instance.startLocation
        }

        // TODO: other fields
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(location?.ref, forKey: .location)
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
            describeLocation()
        } else {
            // FIXME: figure out a portal to use.
            // TODO: update entire UI state.

            triggerEvent("enter_location", in: location, participants: [self],
                         args: [self, location]) {
                location.contents.append(self)
                describeLocation()
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

    func describeLocation() {
        let exits = location.exits.map { ClientValue.string(String(describing: $0.direction)) }
        let contents = location.contents.compactMap { entity -> ClientValue? in
            guard entity != self && entity.isObvious else {
                return nil
            }
            return ClientValue.list([.integer(entity.id),
                                     .string(entity.describeBriefly([.capitalized, .indefinite])),
                                     .string(entity.pose ?? "is here.")])
        }
        sendMessage("showLocation",
                    .string(location.name),
                    .string(location.description),
                    .list(exits),
                    .list(contents))

        let map = Map.init(at: location, radius: 3)
        showMap(map)
    }

    // Bits in the location state sent to the client. Lower bits are derived from
    // the raw values of the exit directions.
    static let questAvailableBit = 1 << 12
    static let questAdvanceableBit = 1 << 13
    static let vendorBit = 1 << 15
    static let trainerBit = 1 << 16

    func showMap(_ map: Map) {
        sendMessage("showMap",
                    .string(location.name),
                    .string("Region Name"), .string("Subregion Name"),  // FIXME:
                    .integer(map.radius),
                    .list(map.cells.map { cell -> ClientValue in

                        var state = 0
                        for exit in cell.location.exits {
                            state |= (1 << exit.direction.rawValue)
                        }

                        print(cell.location.name)
                        print(cell.location.contents)
                        print(cell.location.contents.compactMap { $0 as? Questgiver })

                        if cell.location.contents.contains(where: {
                            if let q = $0 as? Questgiver {
                                print(q, q.offersQuests)
                                return q.offersQuests.contains { $0.acceptableBy(self) }
                            } else {
                                return false
                            }
                        }) {
                            state |= Self.questAvailableBit
                        }

                        return .list([.integer(cell.offset.x),
                                      .integer(cell.offset.y),
                                      .string(cell.location.name),
                                      .string(nil),  // FIXME: icon
                                      .integer(state),
                                      .string(location.surface),
                                      .string(nil),  // FIXME: surrounding
                                      .string(location.domain)])
                    }))
    }
}
