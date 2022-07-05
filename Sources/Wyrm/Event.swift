//
//  Event.swift
//  Wyrm
//

enum EventPhase {
    case allow, before, when, after
}

struct Event: Equatable {
    let phase: EventPhase
    let name: String

    init(_ phase: EventPhase, _ name: String) {
        self.phase = phase
        self.name = name
    }
}

struct EventHandler {
    let event: Event
    let fn: ScriptFunction

    func appliesTo(event: Event, observer: Entity, args: [Value]) -> Bool {
        guard event == self.event && args.count == fn.parameters.count else {
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
func triggerEvent(_ name: String, in location: Location, participants: [Entity],
                  args: [ValueRepresentable], body: () -> Void) -> Bool {
    let args = args.map { $0.toValue() }
    let observers = participants + (location.contents + location.exits.map { $0.portal }).filter {
        !participants.contains($0)
    }

    let allow = Event(.allow, name)
    guard observers.allSatisfy({ $0.allowEvent(allow, args: args) }) else {
        return false
    }

    let before = Event(.before, name)
    observers.forEach { $0.handleEvent(before, args: args) }

    body()

    let when = Event(.when, name)
    participants.forEach { $0.handleEvent(when, args: args) }

    let after = Event(.after, name)
    observers.forEach { $0.handleEvent(after, args: args) }

    return true
}
