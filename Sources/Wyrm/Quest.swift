//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

class Quest: Observer, ValueDictionaryObject {
    var handlers = [EventHandler]()
    var name = ""
    var summary = ""
    var level = 1

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
    ]

    subscript(member: String) -> Value? {
        get {
            return nil
        }
        set {

        }
    }

    func findHandler(phase: EventPhase, event: String) -> ScriptFunction? {
        handlers.firstMap { $0.phase == phase && $0.event == event ? $0.method : nil }
    }
}
