//
//  Avatar.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import CoreFoundation

enum EquippedSlot: Hashable {
    // Weapons and tools.
    case mainHand, offHand

    // Clothing.
    case head, torso, hands, waist, legs, feet

    // Accessories.
    case ears, neck, wrists, leftFinger, rightFinger
}

class Avatar: Entity {
    var level = 0

    // Current location.
    weak var location: Location?

    // Equipped items.
    var equipped = [EquippedSlot:Item?]()

    // A mapping from identifiers of active quests to the current quest state.
    var activeQuests = [String:Value]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [String:CFAbsoluteTime]()

    init(withPrototype prototype: Avatar?) {
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        fatalError("avatars cannot be cloned")
    }
}
