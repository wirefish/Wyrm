//
//  Value.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class ValueList: CustomDebugStringConvertible {
    var values: [Value]

    init<S>(_ elements: S) where S: Sequence, S.Element: ValueRepresentable {
        values = elements.map { $0.toValue() }
    }

    init<S>(_ elements: S) where S: Sequence, S.Element: ReferenceValueRepresentable {
        values = elements.map { $0.toValue() }
    }

    init<S>(_ elements: S) where S: Sequence, S.Element == Value {
        values = [Value].init(elements)
    }

    static func == (lhs: ValueList, rhs: ValueList) -> Bool {
        return lhs === rhs
    }

    var debugDescription: String { "<Wyrm.ValueList \(values)>" }
}

enum Value: Equatable {
    case `nil`
    case boolean(Bool)
    case number(Double)
    case string(String)
    case symbol(String)
    case entity(Entity)
    case exit(Exit)
    case list(ValueList)
    case function(Callable)
    case module(Module)

    var asEntity: Entity? {
        if case let .entity(entity) = self {
            return entity
        } else {
            return nil
        }
    }

    var asValueDictionary: ValueDictionary? {
        switch self {
        case let .entity(e): return e
        case let .module(m): return m
        default: return nil
        }
    }

    // NOTE: This is a very specific notion of equality -- any cases that contain
    // reference types (directly or indirectly) will never compare equal.
    static func == (lhs: Value, rhs: Value) -> Bool {
        if case .nil = lhs, case .nil = rhs {
            return true
        } else if case let .boolean(a) = lhs, case let .boolean(b) = rhs {
            return a == b
        } else if case let .number(a) = lhs, case let .number(b) = rhs {
            return a == b
        } else if case let .string(a) = lhs, case let .string(b) = rhs {
            return a == b
        } else if case let .symbol(a) = lhs, case let .symbol(b) = rhs {
            return a == b
       } else {
            return false
        }
    }
}

protocol ValueDictionary {
    subscript(member: String) -> Value? { get set }
}

protocol Callable {
    func call(_ args: [Value], context: [ValueDictionary]) throws -> Value?
}

// MARK: - representing value types

protocol ValueRepresentable {
    init?(fromValue value: Value)
    func toValue() -> Value
}

extension ValueRepresentable {
    static func enumCase<T>(fromValue value: Value, names: [String:T]) -> T? {
        guard case let .symbol(name) = value else {
            return nil
        }
        return names[name]
    }
}

extension Bool: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .boolean(b) = value else {
            return nil
        }
        self.init(b)
    }

    func toValue() -> Value {
        return .boolean(self)
    }
}

extension Int: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .number(n) = value else {
            return nil
        }
        self.init(exactly: n)
    }

    func toValue() -> Value {
        return .number(Double(self))
    }
}

extension Double: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .number(n) = value else {
            return nil
        }
        self.init(n)
    }

    func toValue() -> Value {
        return .number(self)
    }
}

extension String: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .string(s) = value else {
            return nil
        }
        self.init(s)
    }

    func toValue() -> Value {
        return .string(self)
    }
}

extension NounPhrase: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .string(s) = value else {
            return nil
        }
        self.init(s)
    }

    func toValue() -> Value {
        return .string(singular)
    }
}

extension VerbPhrase: ValueRepresentable {
    init?(fromValue value: Value) {
        guard case let .string(s) = value else {
            return nil
        }
        self.init(s)
    }

    func toValue() -> Value {
        return .string(singular)
    }
}

// MARK: - representing reference types

protocol ReferenceValueRepresentable {
    static func fromValue(_ value: Value) -> ReferenceValueRepresentable?
    func toValue() -> Value
}

extension Entity: ReferenceValueRepresentable {
    static func fromValue(_ value: Value) -> ReferenceValueRepresentable? {
        guard case let .entity(entity) = value else {
            return nil
        }
        return entity
    }

    func toValue() -> Value {
        return .entity(self)
    }
}
