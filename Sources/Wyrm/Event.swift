//
//  Event.swift
//  Wyrm
//

enum EventPhase {
  case allow, before, when, after
}

struct Event: Hashable {
  let phase: EventPhase
  let name: String
}

typealias EventHandlers = [Event:[ScriptFunction]]

extension ScriptFunction {
  // Returns true if the constraints on this function's parameters match the given
  // arguments.
  func appliesTo(args: [Value]) -> Bool {
    guard args.count == parameters.count else {
      return false
    }
    let observer = args.first!
    return zip(args, parameters).allSatisfy { arg, param in
      switch param.constraint {
      case .none:
        return true
      case .self:
        return arg == observer
      case let .prototype(ref):
        let ref = ref.toAbsolute(in: module)
        switch arg {
        case let .entity(entity): return entity.isa(ref)
        case let .quest(quest): return quest.ref == ref
        default: return false
        }
      case let .quest(ref, phase):
        guard let avatar = Avatar.fromValue(arg),
              case let .quest(quest) = World.instance.lookup(ref, context: module) else {
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

protocol Responder: Scope, ValueRepresentable {
  var handlers: EventHandlers { get }
  var delegate: Responder? { get }
}

extension Responder {
  @discardableResult
  func respondTo(_ event: Event, args: [Value]) -> Value {
    let args = [toValue()] + args
    var observer: Responder! = self
    while observer != nil {
      if let fns = observer.handlers[event] {
        let context: [Scope] = [observer]
        for fn in fns {
          if fn.appliesTo(args: args) {
            do {
              switch try fn.call(args, context: context) {
              case let .value(value):
                return value
              case .await:
                return .nil
              case .fallthrough:
                break
              }
            } catch {
              logger.error("error in event handler for \(self) \(event): \(error)")
              return .nil
            }
          }
        }
      }
      observer = observer.delegate
    }
    return .nil
  }

  func allow(_ name: String, args: [Value]) -> Bool {
    return respondTo(Event(phase: .allow, name: name), args: args) != .boolean(false)
  }

  func canRespondTo(phase: EventPhase, name: String) -> Bool {
    return (handlers[Event(phase: phase, name: name)] != nil ||
            (delegate?.canRespondTo(phase: phase, name: name) ?? false))
  }
}

@discardableResult
func triggerEvent(_ event: String, in location: Location, participants: [Entity],
                  args: [ValueRepresentable], body: () -> Void) -> Bool {
  let args = args.map { $0.toValue() }
  let observers = participants + ([location] + location.contents + location.exits).filter {
    !participants.contains($0)
  }

  guard observers.allSatisfy({ $0.allow(event, args: args) }) else {
    return false
  }

  observers.forEach { $0.respondTo(Event(phase: .before, name: event), args: args) }

  body()

  participants.forEach { $0.respondTo(Event(phase: .when, name: event), args: args) }

  observers.forEach { $0.respondTo(Event(phase: .after, name: event), args: args) }

  return true
}
