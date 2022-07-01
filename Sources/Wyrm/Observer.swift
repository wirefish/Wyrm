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

protocol Observer: ValueDictionary {
    // Returns the event handlers that should be called to respond to an event in
    // the order they should be tried. A handler can use the "fallthrough" statement to pass
    // control to the next handler in the list. The observer is the first element of args.
    func matchHandlers(phase: EventPhase, event: String, args: [Value]) -> [EventHandler]

    // Adds a handler that should be considered after all previously-added
    // handlers.
    func addHandler(_ handler: EventHandler)

    func toValue() -> Value
}

extension Observer {
    func handleEvent(_ phase: EventPhase, _ event: String, args: [Value]) {
        // FIXME: handle fallthrough
        let args = [self.toValue()] + args
        let handlers = matchHandlers(phase: phase, event: event, args: args)
        if let handler = handlers.first {
            do {
                let _ = try handler.fn.call(args, context: [self])
            } catch {
                logger.error("error executing event handler: \(error)")
            }
        }
    }

    // A function to help classes implement the protocol's matchHandlers() method.
    func matchHandlers(handlers: [EventHandler], observer: Observer, phase: EventPhase,
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
                    if case let a = arg.asObserver, a === observer {
                        return true
                    } else {
                        return false
                    }
                } else {
                    guard case let .entity(c) = World.instance.lookup(parameter.constraint!,
                                                                      in: handler.fn.module) else {
                        logger.warning("cannot find entity for constraint \(parameter.constraint!)")
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
