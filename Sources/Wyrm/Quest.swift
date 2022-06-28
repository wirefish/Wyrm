//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

class Quest: Observer, ValueDictionary {
    var handlers = [EventHandler]()

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
