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
    case entity(Entity)
    case quest(Quest)
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

// MARK: - ValueList

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

// FIXME: move this?
protocol Callable {
    func call(_ args: [Value], context: [ValueDictionary]) throws -> Value?
}

// MARK: - ValueDictionary

protocol ValueDictionary: AnyObject {
    subscript(member: String) -> Value? { get set }
}

// A pair of functions used to get and set the value of a particular property
// of an object that behaves as a value dictionary.
struct Accessor {
    let get: (ValueDictionaryObject) -> Value
    let set: (ValueDictionaryObject, Value) -> Void
}

protocol ValueDictionaryObject: ValueDictionary {
    static var accessors: [String:Accessor] { get }
}

extension ValueDictionaryObject {
    // A subscript operator to implement ValueDictionary. It uses the accessors
    // registered by a class implementing Facet.
    subscript(member: String) -> Value? {
        get { type(of: self).accessors[member]?.get(self) }
        set { type(of: self).accessors[member]?.set(self, newValue!) }
    }

    // Generic accessor functions to help classes implement the accessors property
    // required by this protocol.

    static func accessor<T: ValueDictionaryObject, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor {
        return Accessor(
            get: {
                return ($0 as! T)[keyPath: keyPath].toValue()
            },
            set: {
                if let value = V.init(fromValue: $1) {
                    ($0 as! T)[keyPath: keyPath] = value
                }
            })
    }

    static func accessor<T: ValueDictionaryObject, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V?>) -> Accessor {
        return Accessor(
            get: {
                return ($0 as! T)[keyPath: keyPath]?.toValue() ?? .nil
            },
            set: {
                guard let value = V.init(fromValue: $1) else {
                    print("cannot set property of type \(V?.self) from value \($1)")
                    return
                }
                ($0 as! T)[keyPath: keyPath] = value
            })
    }

    static func accessor<T: ValueDictionaryObject, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, [V]>) -> Accessor {
        return Accessor(
            get: { .list(ValueList(($0 as! T)[keyPath: keyPath])) },
            set: { (object, value) in
                guard case let .list(list) = value else {
                    return
                }
                (object as! T)[keyPath: keyPath] = list.values.compactMap { V.init(fromValue: $0) }
            })
    }

    static func accessor<T: ValueDictionaryObject, V: RawRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor where V.RawValue == String {
        return Accessor(
            get: {
                let s = ($0 as! T)[keyPath: keyPath].rawValue
                return .symbol(s)
            },
            set: {
                if case let .symbol(s) = $1 {
                    if let v = V.init(rawValue: s) {
                        ($0 as! T)[keyPath: keyPath] = v
                    }
                }
            })
    }

    static func accessor<T: ValueDictionaryObject, V: ReferenceValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor {
        return Accessor(
            get: { ($0 as! T)[keyPath: keyPath].toValue() },
            set: {
                if let value = V.fromValue($1) as? V {
                    ($0 as! T)[keyPath: keyPath] = value
                }
            })
    }

    static func accessor<T: ValueDictionaryObject, V: ReferenceValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, [V]>) -> Accessor {
        return Accessor(
            get: { .list(ValueList(($0 as! T)[keyPath: keyPath])) },
            set: { (object, value) in
                guard case let .list(list) = value else {
                    return
                }
                (object as! T)[keyPath: keyPath] = list.values.compactMap {
                    V.fromValue($0) as? V
                }
            })
    }
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
