//
//  Event.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// A protocol implemented by objects that can observe and respond to
// events.
protocol Observer {
    // Called to allow an observer to accept or reject the event. If this method
    // returns false, the event will not occur. The implementation should provide
    // feedback to the actor describing why the event was rejected.
    func allow(event: Event) -> Bool

    // Called for all observers just before an event occurs.
    func before(event: Event)

    // Called for all observers just after an event occurs.
    func after(event: Event)
}

// Default implementations of Observer methods.
extension Observer {
    func allow(event: Event) -> Bool {
        return true
    }

    func before(event: Event) {
    }

    func after(event: Event) {
    }
}

enum EventPhase {
    case allow, before, after
}

// An enumeration of all possible events.
enum Event {
    case enterLocation(actor: Entity, location: Location, entry: Entity)
}
