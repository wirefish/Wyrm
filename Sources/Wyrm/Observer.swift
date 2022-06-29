//
//  Observer.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

enum EventPhase {
    case allow, before, when, after
}

typealias EventHandler = (phase: EventPhase, event: String, fn: ScriptFunction)

protocol Observer {
    // Return the function that should be called to respond to an event.
    // The observer is passed as the first argument.
    func matchHandlers(observer: Entity, phase: EventPhase, event: String, args: [Value]) -> [EventHandler]

    // Adds a handler that should be considered after all previously-added
    // handlers.
    func addHandler(_ handler: EventHandler)
}

extension Observer {
    func matchHandlers(handlers: [EventHandler], observer: Entity, phase: EventPhase,
                              event: String, args: [Value]) -> [EventHandler] {
        return handlers.compactMap { handler in
            guard handler.phase == phase && handler.event == event else {
                return nil
            }
            guard args.count == handler.fn.parameters.count else {
                return nil
            }
            let match = zip(args, handler.fn.parameters).allSatisfy { arg, parameter in
                if parameter.constraint == nil {
                    return true
                } else if parameter.constraint == Parameter.selfConstraint {
                    if case let .entity(a) = arg, a === observer {
                        return true
                    } else {
                        return false
                    }
                } else {
                    // FIXME: module that function was defined in
                    guard let c = World.instance.lookup(parameter.constraint!, context: nil) else {
                        print("cannot find entity for constraint \(parameter.constraint!)")
                        return false
                    }
                    if case let .entity(a) = arg, a === c {
                        return true
                    } else {
                        return false
                    }
                }
            }
            return match ? handler : nil
        }
    }
}
