//
//  Avatar.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import CoreFoundation

class Avatar: Entity {
    var level = 0

    // A mapping from identifiers of active quests to the current quest state.
    var activeQuests = [String:Value]()

    // A mapping from identifiers of completed quests to the time of completion.
    var completedQuests = [String:CFAbsoluteTime]()

    required init(withPrototype prototype: Entity?) {
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        fatalError("avatars cannot be cloned")
    }
}
