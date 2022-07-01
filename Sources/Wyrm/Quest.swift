//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

protocol Interactable {
    var offers_quests: [Quest] { get }
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

    func matchHandlers(phase: EventPhase, event: String, args: [Value]) -> [EventHandler] {
        return matchHandlers(handlers: handlers, observer: self, phase: phase,
                             event: event, args: args)
    }

    func findHandler(phase: EventPhase, event: String) -> ScriptFunction? {
        handlers.firstMap { $0.phase == phase && $0.event == event ? $0.fn : nil }
    }

    func addHandler(_ handler: EventHandler) {
        handlers.append(handler)
    }

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
