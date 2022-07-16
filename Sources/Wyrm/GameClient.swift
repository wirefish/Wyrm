//
//  GameClient.swift
//  Wyrm
//

let notes = """

All the elements of the client-facing UI state:

top bar: AvatarState: icon, name, race, level, health/energy/mana, auras

left side: [NeighborState]: id, icon, label, opt health bar, state (passive/friendly/neutral/unfriendly)

map: region name + [Location]: id, x, y, exits, icon (e.g. boat), markers (e.g. vendor, quest, etc)

main text and chat text: append only, [(fn, args)]

hotbar: [(Icon, Name, Action)] all are strings, action is implied command/skill to use

bottom right pane has several tabs:

- equipment: [Slot:Item] where item has icon, name

- inventory: [Item] where item has icon, name, quantity

- combat attributes: [String:Double/Int]

- skills: unspent karma + [Skill]: name, rank

The update message can be reduced to an array of (fn, args) that are called in order.

"""

struct ClientCall: Encodable {
    let fn: String
    let args: [ClientValue]
}

enum ClientValue: Encodable {
    case boolean(Bool?)
    case integer(Int?)
    case double(Double?)
    case string(String?)
    case list([ClientValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .boolean(b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case let .integer(i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case let .double(d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case let .string(s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case let .list(list):
            var c = encoder.unkeyedContainer()
            for value in list {
                try c.encode(value)
            }
        }
    }
}

// MARK: - neighbors

struct NeighborProperties: Encodable {
    let key: Int
    let brief: String
    let icon: String?
    let health: Int?
    let maxHealth: Int?

    init(_ entity: PhysicalEntity) {
        key = entity.id
        brief = entity.describeBriefly([])
        icon = entity.icon
        if let creature = entity as? Creature {
            health = creature.currentHealth
            maxHealth = creature.maxHealth
        } else {
            health = nil
            maxHealth = nil
        }
    }
}

extension Avatar {
    func setNeighbors() {
        let args = location.contents.compactMap { entity -> NeighborProperties? in
            entity != self && entity.isObvious(to: self) ? NeighborProperties(entity) : nil
        }
        sendMessage("setNeighbors", args)
    }

    func updateNeighbor(_ entity: PhysicalEntity) {
        sendMessage("updateNeighbor", [NeighborProperties(entity)])
    }

    func removeNeighbor(_ entity: PhysicalEntity) {
        sendMessage("removeNeighbor", [entity.id])
    }
}

struct EquippedItem: Encodable {
    let brief: String
    let icon: String?

    init(_ item: Equipment) {
        brief = item.describeBriefly([])
        icon = item.icon
    }
}

extension Avatar {
    func updateEquipment(_ slots: [EquipmentSlot]) {
        let update = [EquipmentSlot:EquippedItem?].init(uniqueKeysWithValues: slots.map {
            slot -> (EquipmentSlot, EquippedItem?) in
            if let item = equipped[slot] {
                return (slot, EquippedItem(item))
            } else {
                return (slot, nil)
            }
        })
        sendMessage("updateEquipment", [update])
    }
}

struct AvatarState {
    var name: String? {
        didSet {
            changes["name"] = .string(name)
        }
    }

    var level: Int?

    var raceName: String? {
        didSet {
            changes["race"] = .string(raceName)
        }
    }

    var changes = [String:ClientValue]()
}
