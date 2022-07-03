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

