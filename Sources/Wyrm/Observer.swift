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

protocol Observer: ValueDictionary, ReferenceValueRepresentable {
    // Returns the event handlers that should be called to respond to an event in
    // the order they should be tried. A handler can use the "fallthrough" statement to pass
    // control to the next handler in the list. The observer is the first element of args.
    func matchHandlers(phase: EventPhase, event: String, args: [Value]) -> [EventHandler]

    // Adds a handler that should be considered after all previously-added
    // handlers.
    func addHandler(_ handler: EventHandler)
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
        let observer = observer.toValue()
        return handlers.compactMap { handler in
            guard handler.phase == phase && handler.event == event,
                  args.count == handler.fn.parameters.count else {
                return nil
            }
            return zip(args, handler.fn.parameters).allSatisfy { arg, param in
                switch param.constraint {
                case nil:
                    return true
                case Parameter.selfConstraint:
                    return arg == observer
                default:
                    guard let def = World.instance.lookup(param.constraint!, in: handler.fn.module) else {
                        logger.warning("undefined constraint \(param.constraint!)")
                        return false
                    }
                    return arg == def
                }
            } ? handler : nil
        }
    }
}
