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
    let name: String
    var summary = ""

    init(_ name: String) {
        self.name = name
    }

    static let accessors = [
        "summary": accessor(\QuestPhase.summary),
    ]
}

class Quest: ValueDictionaryObject, CustomDebugStringConvertible {
    let ref: ValueRef
    var name = ""
    var summary = ""
    var level = 1
    var phases = [QuestPhase]()

    init(ref: ValueRef) {
        self.ref = ref
    }

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
    ]

    var handlers = [EventHandler]()

    var debugDescription: String { "<Quest \(ref)>" }

    func acceptableBy(_ avatar: Avatar) -> Bool {
        // TODO: call out to quest method
        return (avatar.level >= level
                && avatar.activeQuests[ref] == nil
                && avatar.completedQuests[ref] == nil)
    }

    func completeableBy(_ avatar: Avatar) -> Bool {
        // TODO: what determines this? A specific state value I guess?
        return false
    }
}
