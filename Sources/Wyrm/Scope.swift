//
//  Scope.swift
//  Wyrm
//

// MARK: - Scope

protocol Scope: AnyObject {
  func get(_ member: String) -> Value?
  func set(_ member: String, to value: Value) throws
}

enum AccessError: Error {
  case expected(String)
  case unknownMember(String)
  case readOnlyMember
}

// An Accessor encapsulates a pair of functions used to get and set the value of
// a particular property of an object that behaves as a Scope.
struct Accessor {
  let get: (Scope) -> Value
  let set: (Scope, Value) throws -> Void

  // Creates an accessor that allows read/write access to a property.
  init<T: Scope, V: ValueRepresentable>
  (_ keyPath: ReferenceWritableKeyPath<T, V>) {
    get = { ($0 as! T)[keyPath: keyPath].toValue() }
    set = {
      guard let value = V.fromValue($1) else {
        throw AccessError.expected(String(describing: V.self))
      }
      ($0 as! T)[keyPath: keyPath] = value
    }
  }

  // Creates an accessor that explicitly allows read-only access to a
  // property, even if the provided key path is otherwise writable.
  init<T: Scope, V: ValueRepresentable>
  (readOnly keyPath: KeyPath<T, V>) {
    get = { ($0 as! T)[keyPath: keyPath].toValue() }
    set = { (_, _) in throw AccessError.readOnlyMember }
  }

  // Create a write-only accessor for a type that can be constructed from a Value
  // but not represented by one.
  init<T: Scope, V: ValueConstructible>(writeOnly keyPath: ReferenceWritableKeyPath<T, V>) {
    get = { (_) -> Value in return .nil }
    set = {
      guard let value = V.fromValue($1) else {
        throw AccessError.expected(String(describing: V.self))
      }
      ($0 as! T)[keyPath: keyPath] = value
    }
  }
}

extension Scope {
  func getMember(_ member: String, _ accessors: [String:Accessor]) -> Value? {
    return accessors[member]?.get(self)
  }

  func setMember(_ member: String, to value: Value, _ accessors: [String:Accessor]) throws {
    if let acc = accessors[member] {
      try acc.set(self, value)
    } else {
      throw AccessError.unknownMember(member)
    }
  }

  func setMember(_ member: String, to value: Value, _ accessors: [String:Accessor],
                 or fn: () throws -> Void) throws {
    if let acc = accessors[member] {
      try acc.set(self, value)
    } else {
      try fn()
    }
  }
}
