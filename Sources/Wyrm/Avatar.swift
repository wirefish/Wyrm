//
//  Avatar.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import CoreFoundation

enum EquippedSlot: String, CodingKeyRepresentable, Hashable, Encodable {
    // Weapons and tools.
    case mainHand, offHand

    // Clothing.
    case head, torso, hands, waist, legs, feet

    // Accessories.
    case ears, neck, wrists, leftFinger, rightFinger
}

struct QuestState {
    let phase: String
    var state: Value
}

class Avatar: Entity {
    var level = 1

    // Current location.
    weak var location: Location?

    // Equipped items.
    var equipped = [EquippedSlot:Item?]()

    // A mapping from identifiers of active quests to their current state.
    var activeQuests = [ValueRef:QuestState]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [ValueRef:CFAbsoluteTime]()
}

extension Avatar: Encodable {
    enum CodingKeys: CodingKey {
        case level, location, equipped, activeQuests
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(level, forKey: .level)
        try container.encode(location?.ref, forKey: .location)
        try container.encode(equipped, forKey: .equipped)
        // try container.encode(activeQuests, forKey: .activeQuests)
    }
}
