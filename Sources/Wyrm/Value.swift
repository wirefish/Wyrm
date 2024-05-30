//
//  Value.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// MARK: - Value

enum Value: Equatable {
  case `nil`
  case boolean(Bool)
  case number(Double)
  case string(String)
  case symbol(String)
  case ref(Ref)
  case entity(Entity)
  case quest(Quest)
  case race(Race)
  case skill(Skill)
  case list(ValueList)
  case function(Callable)
  case module(Module)
  case future((@escaping () -> Void) -> Void)

  func asEntity<T: Entity>(_ t: T.Type) -> T? {
    if case let .entity(entity) = self {
      return entity as? T
    } else {
      return nil
    }
  }

  var asValueDictionary: ValueDictionary? {
    switch self {
    case let .entity(e): return e
    case let .quest(q): return q
    case let .race(r): return r
    case let .skill(s): return s
    case let .module(m): return m
    default: return nil
    }
  }

  // NOTE: This is only implemented for required cases. Some values will never
  // compare equal.
  static func == (lhs: Value, rhs: Value) -> Bool {
    switch lhs {
    case .nil: if case .nil = rhs { return true }
    case let .boolean(a): if case let .boolean(b) = rhs { return a == b }
    case let .number(a): if case let .number(b) = rhs { return a == b }
    case let .string(a): if case let .string(b) = rhs { return a == b }
    case let .symbol(a): if case let .symbol(b) = rhs { return a == b }
    case let .ref(a): if case let .ref(b) = rhs { return a == b }
    case let .entity(a): if case let .entity(b) = rhs { return a == b }
    case let .quest(a): if case let .quest(b) = rhs { return a === b }
    case let .race(a): if case let .race(b) = rhs { return a === b }
    default: break
    }
    return false
  }
}

// MARK: - ValueList

final class ValueList: CustomDebugStringConvertible {
  var values: [Value]

  init<S>(_ elements: S) where S: Sequence, S.Element: ValueRepresentable {
    values = elements.map { $0.toValue() }
  }

  init<S>(_ elements: S) where S: Sequence, S.Element == Value {
    values = [Value].init(elements)
  }

  static func == (lhs: ValueList, rhs: ValueList) -> Bool {
    return lhs === rhs
  }

  var debugDescription: String { "<ValueList \(values)>" }
}

// MARK: - ValueDictionary

protocol ValueDictionary: AnyObject {
  func get(_ member: String) -> Value?
  func set(_ member: String, to value: Value) throws
}

enum ValueError: Error {
  case expected(String)
  case unknownMember(String)
  case readOnlyMember
}

// A pair of functions used to get and set the value of a particular property
// of an object that behaves as a value dictionary.
struct Accessor {
  let get: (ValueDictionary) -> Value
  let set: (ValueDictionary, Value) throws -> Void

  // Creates an accessor that allows read/write access to a property.
  init<T: ValueDictionary, V: ValueRepresentable>
  (_ keyPath: ReferenceWritableKeyPath<T, V>) {
    get = { ($0 as! T)[keyPath: keyPath].toValue() }
    set = {
      guard let value = V.fromValue($1) else {
        throw ValueError.expected(String(describing: V.self))
      }
      ($0 as! T)[keyPath: keyPath] = value
    }
  }

  // Creates an accessor that explicitly allows read-only access to a
  // property, even if the provided key path is otherwise writable.
  init<T: ValueDictionary, V: ValueRepresentable>
  (readOnly keyPath: KeyPath<T, V>) {
    get = { ($0 as! T)[keyPath: keyPath].toValue() }
    set = { (_, _) in throw ValueError.readOnlyMember }
  }
}

extension ValueDictionary {
  func getMember(_ member: String, _ accessors: [String:Accessor]) -> Value? {
    return accessors[member]?.get(self)
  }

  func setMember(_ member: String, to value: Value, _ accessors: [String:Accessor]) throws {
    if let acc = accessors[member] {
      try acc.set(self, value)
    } else {
      throw ValueError.unknownMember(member)
    }
  }

  func setMember(_ member: String, to value: Value, _ accessors: [String:Accessor], _ elseFn: () throws -> Void) throws {
    if let acc = accessors[member] {
      try acc.set(self, value)
    } else {
      try elseFn()
    }
  }
}

// MARK: - representing value types

protocol ValueRepresentable {
  static func fromValue(_ value: Value) -> Self?
  func toValue() -> Value
}

extension ValueRepresentable {
  static func fromValue(_ value: Value?) -> Self? {
    if let value = value {
      return fromValue(value)
    } else {
      return nil
    }
  }
}

extension Bool: ValueRepresentable {
  static func fromValue(_ value: Value) -> Bool? {
    guard case let .boolean(b) = value else {
      return nil
    }
    return b
  }

  func toValue() -> Value {
    return .boolean(self)
  }
}

extension Int: ValueRepresentable {
  static func fromValue(_ value: Value) -> Int? {
    guard case let .number(n) = value else {
      return nil
    }
    return Int(exactly: n)
  }

  func toValue() -> Value {
    return .number(Double(self))
  }
}

extension Double: ValueRepresentable {
  static func fromValue(_ value: Value) -> Double? {
    guard case let .number(n) = value else {
      return nil
    }
    return n
  }

  func toValue() -> Value {
    return .number(self)
  }
}

extension String: ValueRepresentable {
  static func fromValue(_ value: Value) -> String? {
    switch value {
    case let .string(s): return s
    case let .symbol(s): return s
    default: return nil
    }
  }

  func toValue() -> Value {
    return .string(self)
  }
}

extension NounPhrase: ValueRepresentable {
  static func fromValue(_ value: Value) -> NounPhrase? {
    guard case let .string(s) = value else {
      return nil
    }
    return NounPhrase(s)
  }

  func toValue() -> Value {
    // FIXME: This isn't right but it really doesn't matter.
    return .string(singular)
  }
}

extension ValueList: ValueRepresentable {
  static func fromValue(_ value: Value) -> ValueList? {
    guard case let .list(list) = value else {
      return nil
    }
    return list
  }

  func toValue() -> Value {
    return .list(self)
  }
}

extension Value: ValueRepresentable {
  static func fromValue(_ value: Value) -> Value? {
    return value
  }

  func toValue() -> Value {
    return self
  }
}

extension Array: ValueRepresentable where Element: ValueRepresentable {
  static func fromValue(_ value: Value) -> Self? {
    guard case let .list(list) = value else {
      return nil
    }
    return list.values.compactMap { Element.fromValue($0) }
  }

  func toValue() -> Value {
    return .list(ValueList(self.map { $0.toValue() }))
  }
}

extension Optional: ValueRepresentable where Wrapped: ValueRepresentable {
  static func fromValue(_ value: Value) -> Self? {
    if value == .nil {
      return .some(.none)
    } else if let wrapped = Wrapped.fromValue(value) {
      return .some(wrapped)
    } else {
      return .none
    }
  }

  func toValue() -> Value {
    switch self {
    case .none: return .nil
    case let .some(wrapped): return wrapped.toValue()
    }
  }
}

// MARK: - representing enums

protocol ValueRepresentableEnum: CaseIterable, ValueRepresentable {
  static var names: [String:Self] { get }
}

extension ValueRepresentableEnum {
  static func fromValue(_ value: Value) -> Self? {
    guard case let .symbol(name) = value else {
      return nil
    }
    return Self.names[name]
  }

  func toValue() -> Value {
    return .symbol(String(describing: self))
  }
}

// MARK: - representing referenced objects

extension Entity: ValueRepresentable {
  static func fromValue(_ value: Value) -> Self? {
    switch value {
    case let .entity(entity):
      return entity as? Self
    case let .ref(ref):
      return World.instance.lookup(ref)?.asEntity(Self.self)
    default:
      return nil
    }
  }

  func toValue() -> Value {
    return .entity(self)
  }
}

extension Quest: ValueRepresentable {
  static func fromValue(_ value: Value) -> Quest? {
    switch value {
    case let .quest(quest):
      return quest
    case let .ref(ref):
      guard case let .quest(quest) = World.instance.lookup(ref) else {
        return nil
      }
      return quest
    default:
      return nil
    }
  }

  func toValue() -> Value {
    return .quest(self)
  }
}

extension Race: ValueRepresentable {
  static func fromValue(_ value: Value) -> Race? {
    switch value {
    case let .race(race):
      return race
    case let .ref(ref):
      if case let .race(race) = World.instance.lookup(ref) {
        return race
      } else {
        return nil
      }
    default:
      return nil
    }
  }

  func toValue() -> Value {
    return .race(self)
  }
}
