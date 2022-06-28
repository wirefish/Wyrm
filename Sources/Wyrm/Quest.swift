//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

class Questgiver: Facet {
    var offers_quests = [Quest]()

    static let isMutable = false

    required init() {
    }

    func clone() -> Facet {
        let f = Questgiver()
        f.offers_quests = offers_quests
        return f
    }

    static let accessors = [
        "offers_quests": accessor(\Questgiver.offers_quests),
    ]
}

class Quest: Observer, ValueDictionaryObject, CustomDebugStringConvertible {
    let id: String
    var name = ""
    var summary = ""
    var level = 1

    init(id: String) {
        self.id = id
    }

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
    ]

    var handlers = [EventHandler]()

    func findHandler(phase: EventPhase, event: String) -> ScriptFunction? {
        handlers.firstMap { $0.phase == phase && $0.event == event ? $0.method : nil }
    }

    func addHandler(_ handler: EventHandler) {
        handlers.append(handler)
    }

    var debugDescription: String { "<Wyrm.Quest \(id)>" }

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
