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
                let ref = ref.toAbsolute(in: fn.module)
                switch arg {
                case let .entity(entity): return entity.isa(ref)
                case let .quest(quest): return quest.ref == ref
                default: return false
                }
            case let .quest(ref, phase):
                guard let avatar = Avatar.fromValue(arg),
                      case let .quest(quest) = World.instance.lookup(ref, context: fn.module) else {
                    return false
                }
                switch phase {
                case "available": return quest.acceptableBy(avatar)
                case "offered": return (avatar.offer as? QuestOffer)?.quest === quest
                case "complete": return avatar.completedQuests[quest.ref] != nil
                case "incomplete": return avatar.activeQuests[quest.ref]?.phase == phase
                default: return avatar.activeQuests[quest.ref]?.phase == phase
                }
            case let .race(ref):
                return Avatar.fromValue(arg)?.race?.ref == ref
            case let .equipped(ref):
                return Avatar.fromValue(arg)?.hasEquipped(ref) ?? false
            }
        }
    }
}

@discardableResult
func triggerEvent(_ event: String, in location: Location, participants: [Entity],
                  args: [ValueRepresentable], body: () -> Void) -> Bool {
    let args = args.map { $0.toValue() }
    let observers = participants + ([location] + location.contents + location.exits).filter {
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
