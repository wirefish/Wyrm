//
//  Entity.swift
//  Wyrm
//

// MARK: - Whatevs

@dynamicMemberLookup
class Proto {
  let ref: Ref
  let proto: Proto?

  var brief: NounPhrase?
  private var members = [String:Value]()

  init(ref: Ref, proto: Proto?) {
    self.ref = ref
    self.proto = proto
  }

  subscript(dynamicMember name: String) -> Value? {
    get { print("getting Value \(name)"); return members[name] ?? proto?[dynamicMember: name] }
    set { print("setting Value \(name)"); members[name] = newValue }
  }

  subscript<T: ValueRepresentable>(dynamicMember name: String) -> T? {
    get { print("getting \(T.self) \(name)"); return T.fromValue(members[name]) }
    set { print("setting \(T.self) \(name)"); members[name] = newValue?.toValue() }
  }

  // Methods used when evaluating scripts.

  func get(_ member: String) -> Value? {
    members[member] ?? proto?.get(member)
  }

  func set(_ member: String, to value: Value) throws {
    switch member {
    case "brief":
      guard case let .string(s) = value else {
        throw ValueError.expected("String")
      }
      brief = NounPhrase(s)
    default:
      members[member] = value
    }
  }

}

// MARK: - Prototype

@propertyWrapper
struct Member<T: ValueRepresentable> {
  var member: T?
  var wrappedValue: Value {
    get { return member.toValue() }
    set { member = T.self.fromValue(newValue) }
  }
}

class Prototype: ValueDictionary {
  let ref: Ref
  let parent: Prototype?
  var handlers = [EventHandler]()
  var extraProperties = [String:Value]()

  required init(ref: Ref, parent: Prototype? = nil) {
    self.ref = ref
    self.parent = parent
  }

  func get(_ property: String) -> Value? {
    return extraProperties[property]
  }

  func set(_ property: String, to value: Value) throws {
    extraProperties[property] = value
  }

  func specialize(ref: Ref) -> Self {
    return Self(ref: ref, parent: self)
  }

  func instantiate() -> Instance {
    fatalError("instantiate() not implemented for \(type(of: self))")
  }
}

extension Prototype: CustomStringConvertible {
  var description: String {
    "<\(type(of: self)) \(ref)>"
  }
}

// MARK: Instance

class Instance: ValueDictionary, CustomStringConvertible {
  static var idIterator = (1...).makeIterator()

  let id = idIterator.next()!
  var extraProperties = [String:Value]()

  func get(_ property: String) -> Value? {
    return extraProperties[property]
  }

  func set(_ property: String, to value: Value) throws {
    extraProperties[property] = value
  }

  var description: String {
    "<\(type(of: self)) #\(id)>"
  }
}

class InstanceOf<T: Prototype>: Instance {
  let prototype: T

  init(prototype: T) {
    self.prototype = prototype
  }

  override var description: String {
    "<\(type(of: self)) #\(id) \(prototype.ref)>"
  }
}

// MARK: - test for items

class ItemPrototype: Prototype {
  var level = 0
  var stackLimit = 0

  private static let accessors = [
    "level": Accessor(\ItemPrototype.level),
    "stackLimit": Accessor(\ItemPrototype.stackLimit),
  ]

  override func get(_ property: String) -> Value? {
    getMember(property, Self.accessors) ?? super.get(property)
  }

  override func set(_ property: String, to value: Value) throws {
    try setMember(property, to: value, Self.accessors) { try super.set(property, to: value) }
  }

  override func instantiate() -> Instance {
    ItemInstance(prototype: self)
  }
}

class ItemInstance: InstanceOf<ItemPrototype> {
  var count = 1

  private static let accessors = [
    "count": Accessor(\Item.count),
  ]

  override func get(_ property: String) -> Value? {
    getMember(property, Self.accessors) ?? super.get(property) ?? prototype.get(property)
  }

  override func set(_ property: String, to value: Value) throws {
    // FIXME:
  }

  func split(count: Int) -> ItemInstance {
    self.count -= count
    let result = ItemInstance(prototype: self.prototype)
    result.count = count
    return result
  }
}

// MARK: - event handling

extension InstanceOf {
  @discardableResult
  final func handleEvent(_ phase: EventPhase, _ event: String, args: [Value]) -> Value {
    // FIXME: let args = [.instance(self)] + args
    var prototype: Prototype! = self.prototype
    while prototype != nil {
      for handler in prototype.handlers {
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
      prototype = prototype.parent
    }
    return .nil
  }

  final func allowEvent(_ event: String, args: [Value]) -> Bool {
    return handleEvent(.allow, event, args: args) != .boolean(false)
  }

  final func canRespondTo(phase: EventPhase, event: String) -> Bool {
    var prototype: Prototype! = self.prototype
    while prototype != nil {
      if prototype.handlers.contains(where: { $0.phase == phase && $0.event == event }) {
        return true
      }
      prototype = prototype.parent
    }
    return false
  }
}

// MARK: - gmm

@dynamicMemberLookup
class Entity: ValueDictionary {
  static var idIterator = (1...).makeIterator()

  let id = idIterator.next()!
  var ref: Ref?
  let prototype: Entity?
  var handlers = [EventHandler]()
  var extraMembers = [String:Value]()

  required init(withPrototype prototype: Entity? = nil) {
    self.prototype = prototype
  }

  func copyProperties(from other: Entity) {
    extraMembers = other.extraMembers
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
    extraMembers[name]
  }

  final func isa(_ ref: Ref) -> Bool {
    return ref == self.ref || (prototype?.isa(ref) ?? false)
  }

  func get(_ member: String) -> Value? {
    return extraMembers[member]
  }

  func set(_ member: String, to value: Value) throws {
    extraMembers[member] = value
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
