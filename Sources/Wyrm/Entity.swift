//
//  Entity.swift
//  Wyrm
//

@dynamicMemberLookup
class Entity: Scope {
  static var idIterator = (1...).makeIterator()
  static let initializerMember = "__INIT__"

  let id = idIterator.next()!
  var ref: Ref?
  let prototype: Entity?

  var members = [String:Value]()
  var handlers = [EventHandler]()

  required init(withPrototype prototype: Entity? = nil) {
    self.prototype = prototype
  }

  init(ref: Ref, prototype: Entity?, initializer: Callable?) {
    self.ref = ref
    self.prototype = prototype
    if let initializer = initializer {
      members[Self.initializerMember] = .function(initializer)
    }
  }

  func copyProperties(from other: Entity) {
    members = other.members
  }

  // Creates a new entity of the same type with a copy of this entity's properties.
  // If this is a "named" entity (i.e. one defined at the top level of a script file
  // and therefore with a non-nil ref), then the new entity uses this entity as its
  // prototype. Otherwise, the new entity shares a prototype with this entity.
  final func clone() -> Self {
    let prototype = self.ref == nil ? self.prototype : self
    let entity = Self.init(withPrototype: prototype)
    entity.copyProperties(from: self)
    return entity
  }

  subscript(dynamicMember name: String) -> Value? {
    get { get (name) }
  }

  final func isa(_ ref: Ref) -> Bool {
    return ref == self.ref || (prototype?.isa(ref) ?? false)
  }

  func get(_ member: String) -> Value? {
    return members[member]
  }

  func set(_ member: String, to value: Value) throws {
    members[member] = value
  }
}

extension Entity: Hashable {
  static func == (_ lhs: Entity, _ rhs: Entity) -> Bool {
    return lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension Entity: CustomDebugStringConvertible {
  var debugDescription: String {
    if let ref = ref {
      return "<\(type(of: self)) ref=\(ref)>"
    } else if let protoRef = prototype?.ref {
      return "<\(type(of: self)) id=\(id) proto=\(protoRef)>"
    } else {
      return "<\(type(of: self)) id=\(id) proto=??>"
    }
  }
}

extension Entity {
  @discardableResult
  final func handleEvent(_ phase: EventPhase, _ event: String, args: [Value]) -> Value {
    let args = [.entity(self)] + args
    var observer: Entity! = self
    while observer != nil {
      for handler in observer.handlers {
        guard handler.appliesTo(phase: phase, event: event, args: args) else {
          continue
        }
        do {
          switch try handler.fn.call(args, context: [self]) {
          case let .value(value):
            return value
          case .await:
            return .nil
          case .fallthrough:
            break
          }
        } catch {
          logger.error("error in event handler for \(self) \(phase) \(event): \(error)")
          return .nil
        }
      }
      observer = observer.prototype
    }
    return .nil
  }

  final func allowEvent(_ event: String, args: [Value]) -> Bool {
    return handleEvent(.allow, event, args: args) != .boolean(false)
  }

  final func canRespondTo(phase: EventPhase, event: String) -> Bool {
    if handlers.contains(where: { $0.phase == phase && $0.event == event }) {
      return true
    } else {
      return prototype?.canRespondTo(phase: phase, event: event) ?? false
    }
  }
}
