//
//  Observer.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

enum EventPhase {
    case allow, before, when, after
}

typealias EventHandler = (phase: EventPhase, event: String, method: ScriptFunction)

protocol Observer {
    // Return the function that should be called to respond to an event.
    // The observer is passed as the first argument.
    func findHandler(phase: EventPhase, event: String) -> ScriptFunction?
}
