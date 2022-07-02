//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

protocol Interactable {
    var offers_quests: [Quest] { get }
    // TODO: interaction_verbs that are like implied commands, if the user enters an unknown
    // command it parses the rest of the input and matches it against entities at the current
    // location, then if they have a matching verb it generates events for that verb.
}

class QuestPhase: ValueDictionaryObject {
    var summary = ""
    var handlers = [EventHandler]()

    static let accessors = [
        "summary": accessor(\QuestPhase.summary),
    ]
}

class Quest: ValueDictionaryObject, CustomDebugStringConvertible {
    let id: String
    var name = ""
    var summary = ""
    var level = 1
    var phases = [QuestPhase]()

    init(id: String) {
        self.id = id
    }

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
    ]

    var handlers = [EventHandler]()

    var debugDescription: String { "<Quest \(id)>" }

    func acceptableBy(_ avatar: Avatar) -> Bool {
        // TODO: call out to quest method
        return (avatar.level >= level
                && avatar.activeQuests[id] == nil
                && avatar.completedQuests[id] == nil)
    }

    func completeableBy(_ avatar: Avatar) -> Bool {
        // TODO: what determines this? A specific state value I guess?
        return false
    }
}
