//
//  Value.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

enum Value {
    case `nil`
    case boolean(Bool)
    case number(Double)
    case string(String)
    case symbol(String)
    case entity(Entity)
    case exit(Exit)
    case list([Value])
    case function(ScriptFunction)
}

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
