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
    case list([Value])
}

protocol ValueRepresentable {
    init?(fromValue value: Value)
    func toValue() -> Value
}

extension ValueRepresentable {
    static func enumCase<T>(fromValue value: Value, names: [String:T]) -> T? {
        if case let .symbol(name) = value {
            return names[name]
        } else {
            return nil
        }
    }
}

extension NounPhrase: ValueRepresentable {
    init?(fromValue value: Value) {
        if case let .string(s) = value {
            self.init(s)
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        return .string(singular)
    }
}
