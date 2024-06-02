//
//  Value.swift
//  Wyrm
//

// MARK: - Value

enum Value: Equatable {
  case `nil`
  case boolean(Bool)
  case number(Double)
  case string(String)
  case symbol(String)
  case range(ClosedRange<Int>)
  case list([Value])
  case entity(Entity)
  case stack(ItemStack)
  case region(Region)
  case quest(Quest)
  case phase(QuestPhase)
  case race(Race)
  case skill(Skill)
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

  var asScope: Scope? {
    switch self {
    case let .entity(e): return e
    case let .region(r): return r
    case let .quest(q): return q
    case let .phase(p): return p
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
    case let .entity(a): if case let .entity(b) = rhs { return a == b }
    case let .quest(a): if case let .quest(b) = rhs { return a === b }
    case let .race(a): if case let .race(b) = rhs { return a === b }
    default: break
    }
    return false
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

extension Value: ValueRepresentable {
  static func fromValue(_ value: Value) -> Value? { value }
  func toValue() -> Value { self }
}

extension Bool: ValueRepresentable {
  static func fromValue(_ value: Value) -> Bool? {
    if case let .boolean(b) = value { b } else { nil }
  }
  func toValue() -> Value { .boolean(self) }
}

extension Int: ValueRepresentable {
  static func fromValue(_ value: Value) -> Int? {
    guard case let .number(n) = value else {
      return nil
    }
    return Int(exactly: n)
  }

  func toValue() -> Value { .number(Double(self)) }
}

extension Double: ValueRepresentable {
  static func fromValue(_ value: Value) -> Double? {
    guard case let .number(n) = value else {
      return nil
    }
    return n
  }

  func toValue() -> Value { .number(self) }
}

extension String: ValueRepresentable {
  static func fromValue(_ value: Value) -> String? {
    switch value {
    case let .string(s): return s
    case let .symbol(s): return s
    default: return nil
    }
  }

  func toValue() -> Value { .string(self) }
}

extension ClosedRange<Int>: ValueRepresentable {
  static func fromValue(_ value: Value) -> ClosedRange<Int>? {
    guard case let .range(range) = value else {
      return nil
    }
    return range
  }

  func toValue() -> Value { .range(self) }
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

extension Array: ValueRepresentable where Element: ValueRepresentable {
  static func fromValue(_ value: Value) -> Self? {
    guard case let .list(list) = value else {
      return nil
    }
    return list.compactMap { Element.fromValue($0) }
  }

  func toValue() -> Value { .list(self.map{ $0.toValue() }) }
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
    guard case let .entity(entity) = value else {
      return nil
    }
    return entity as? Self
  }
  func toValue() -> Value { .entity(self) }
}

extension Quest: ValueRepresentable {
  static func fromValue(_ value: Value) -> Quest? {
    guard case let .quest(quest) = value else {
      return nil
    }
    return quest
  }

  func toValue() -> Value {
    return .quest(self)
  }
}

extension QuestPhase: ValueRepresentable {
  static func fromValue(_ value: Value) -> QuestPhase? {
    if case let .phase(phase) = value {
      phase
    } else {
      nil
    }
  }
  func toValue() -> Value { .phase(self) }
}

extension Race: ValueRepresentable {
  static func fromValue(_ value: Value) -> Race? {
    guard case let .race(race) = value else {
      return nil
    }
    return race
  }
  func toValue() -> Value { .race(self) }
}

extension Skill: ValueRepresentable {
  static func fromValue(_ value: Value) -> Skill? {
    guard case let .skill(skill) = value else {
      return nil
    }
    return skill
  }
  func toValue() -> Value { .skill(self) }
}

extension Region: ValueRepresentable {
  static func fromValue(_ value: Value) -> Region? {
    guard case let .region(region) = value else {
      return nil
    }
    return region
  }
  func toValue() -> Value { .region(self) }
}
