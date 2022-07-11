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

    func appliesTo(phase: EventPhase, event: String, args: [Value]) -> Bool {
        guard phase == self.phase && event == self.event && args.count == fn.parameters.count else {
            return false
        }

        let observer = args.first!
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
            case let .quest(ref, phase):
                guard let avatar = arg.asEntity(Avatar.self),
                      case let .quest(quest) = World.instance.lookup(ref, context: fn.module) else {
                    return false
                }
                if phase == "available" {
                    return quest.acceptableBy(avatar)
                } else if phase == "complete" {
                    return avatar.completedQuests[quest.ref] != nil
                } else {
                    return avatar.activeQuests[ref]?.phase == phase
                }
            }
        }
    }
}

@discardableResult
func triggerEvent(_ event: String, in location: Location, participants: [Entity],
                  args: [ValueRepresentable], body: () -> Void) -> Bool {
    let args = args.map { $0.toValue() }
    let observers = participants + (location.contents + location.exits).filter {
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
