//
//  Entity.swift
//  Wyrm
//

class Entity: Scope, Responder {
  static var idIterator = (1...).makeIterator()

  let id = idIterator.next()!
  var ref: Ref?
  let prototype: Entity?

  var members = [String:Value]()

  var handlers = EventHandlers()
  var delegate: Responder? { prototype }

  required init(prototype: Entity? = nil) {
    self.prototype = prototype
  }

  init(ref: Ref, prototype: Entity?) {
    self.ref = ref
    self.prototype = prototype
  }

  // Overridden by subclasses to copy any desired properties to a new clone.
  func copyProperties(from other: Entity) {}

  // Creates a new instance of an Entity subclass. If self has a non-nil ref
  // (because it was defined at the top level of a script file) then the new
  // entity will have this entity as its prototype. Otherwise, the new entity
  // shares a prototype with this entity.
  final func clone() -> Self {
    let prototype = (self.ref == nil) ? self.prototype : self
    let entity = Self.init(prototype: prototype)
    entity.copyProperties(from: self)
    return entity
  }

  final func isa(_ ref: Ref) -> Bool {
    return ref == self.ref || (prototype?.isa(ref) ?? false)
  }

  func get(_ member: String) -> Value? {
    return members[member] ?? prototype?.get(member)
  }

  func set(_ member: String, to value: Value) throws {
    members[member] = value
  }
}

extension Entity: Hashable {
  static func == (_ lhs: Entity, _ rhs: Entity) -> Bool {
    return lhs === rhs
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
