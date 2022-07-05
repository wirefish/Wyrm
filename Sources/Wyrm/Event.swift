//
//  Event.swift
//  Wyrm
//

enum EventPhase {
    case allow, before, when, after
}

struct EventHandler {
    let phase: EventPhase
    let event: String
    let fn: ScriptFunction

    func appliesTo(phase: EventPhase, event: String, observer: Entity, args: [Value]) -> Bool {
        guard phase == self.phase && event == self.event && args.count == fn.parameters.count else {
            return false
        }

        let observer: Value = .entity(observer)
        return zip(args, fn.parameters).allSatisfy { arg, param in
            switch param.constraint {
            case .none:
                return true
            case .self:
                return arg == observer
            case let .prototype(ref):
                guard case let .entity(entity) = arg else {
                    return false
                }
                return entity.extends(ref)
            default:
                fatalError("inimplemented constraint type")
            }
        }
    }
}

@discardableResult
func triggerEvent(_ event: String, in location: Location, participants: [Entity],
                  args: [ValueRepresentable], body: () -> Void) -> Bool {
    let args = args.map { $0.toValue() }
    let observers = participants + (location.contents + location.exits.map { $0.portal }).filter {
        !participants.contains($0)
    }

    guard observers.allSatisfy({ $0.allowEvent(event, args: args) }) else {
        return false
    }

    observers.forEach { $0.handleEvent(.before, event, args: args) }

    body()

    participants.forEach { $0.handleEvent(.when, event, args: args) }

    observers.forEach { $0.handleEvent(.after, event, args: args) }

    return true
}
