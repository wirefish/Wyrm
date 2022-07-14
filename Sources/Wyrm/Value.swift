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
    case ref(ValueRef)
    case entity(Entity)
    case quest(Quest)
    case race(Race)
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

class ValueList: CustomDebugStringConvertible {
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

// A pair of functions used to get and set the value of a particular property
// of an object that behaves as a value dictionary.
struct Accessor {
    let get: (ValueDictionary) -> Value
    let set: (ValueDictionary, Value) -> Void
}

protocol ValueDictionary: AnyObject {
    subscript(member: String) -> Value? { get set }
}

extension ValueDictionary {
    // Generic accessor functions to help classes implement the accessors property
    // required by this protocol.

    static func accessor<T: ValueDictionary, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor {
        return Accessor(
            get: {
                return ($0 as! T)[keyPath: keyPath].toValue()
            },
            set: {
                if let value = V.fromValue($1) {
                    ($0 as! T)[keyPath: keyPath] = value
                }
            })
    }

    static func accessor<T: ValueDictionary, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, V?>) -> Accessor {
        return Accessor(
            get: {
                return ($0 as! T)[keyPath: keyPath]?.toValue() ?? .nil
            },
            set: {
                guard let value = V.fromValue($1) else {
                    print("cannot set property of type \(V?.self) from value \($1)")
                    return
                }
                ($0 as! T)[keyPath: keyPath] = value
            })
    }

    static func accessor<T: ValueDictionary, V: ValueRepresentable>
    (_ keyPath: ReferenceWritableKeyPath<T, [V]>) -> Accessor {
        return Accessor(
            get: { .list(ValueList(($0 as! T)[keyPath: keyPath])) },
            set: { (object, value) in
                guard case let .list(list) = value else {
                    return
                }
                (object as! T)[keyPath: keyPath] = list.values.compactMap { V.fromValue($0) }
            })
    }

    // FIXME: get rid of this
    static func accessor<T: ValueDictionary, V: RawRepresentable>
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
}

// MARK: - representing value types

protocol ValueRepresentable {
    static func fromValue(_ value: Value) -> Self?
    func toValue() -> Value
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

extension Value: ValueRepresentable {
    static func fromValue(_ value: Value) -> Value? {
        return value
    }

    func toValue() -> Value {
        return self
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
        guard let v = Self.names[name] else {
            return nil
        }
        return v
    }

    func toValue() -> Value {
        return .symbol(String(describing: self))
    }
}

extension Entity: ValueRepresentable {
    static func fromValue(_ value: Value) -> Self? {
        switch value {
        case let .entity(entity):
            return entity as? Self
        case let .ref(ref):
            return World.instance.lookup(ref, context: nil)?.asEntity(Self.self)
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
            guard case let .quest(quest) = World.instance.lookup(ref, context: nil) else {
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
        guard case let .race(race) = value else {
            return nil
        }
        return race
    }

    func toValue() -> Value {
        return .race(self)
    }
}
