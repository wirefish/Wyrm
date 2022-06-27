//
//  Value.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

enum Value: Equatable {
    case `nil`
    case boolean(Bool)
    case number(Double)
    case string(String)
    case symbol(String)
    case entity(Entity)
    case exit(Exit)
    case list([Value])
    case function(ScriptFunction)
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
}

protocol ValueDictionary {
    subscript(member: String) -> Value? { get set }
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
