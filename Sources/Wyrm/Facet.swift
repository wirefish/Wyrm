//
//  Facet.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// A protocol for an object that encapsulates a collection of related
// properties which are necessary in order to interact with other objects
// in a specific way.
protocol Facet: AnyObject {

    static var isMutable: Bool { get }

    static var accessors: [String:Accessor] { get }

    init()
    
    func clone() -> Facet
}

// A pair of functions used to get and set the value of a particular property
// of a Facet.
struct Accessor {
    let get: (Facet) -> Value
    let set: (Facet, Value) -> Void
}

extension Facet {
    // A subscript operator that uses accessors registered by a class
    // to get or set a property by name.
    subscript(member: String) -> Value? {
        get { type(of: self).accessors[member]?.get(self) }
        set { type(of: self).accessors[member]?.set(self, newValue!) }
    }

    // Generic accessor functions to help classes implement the accessors property
    // required by this protocol.

    static func accessor<T: Facet, V: ValueRepresentable>(_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor {
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

    static func accessor<T: Facet, V: ValueRepresentable>(_ keyPath: ReferenceWritableKeyPath<T, V?>) -> Accessor {
        return Accessor(
            get: {
                return ($0 as! T)[keyPath: keyPath]?.toValue() ?? .nil
            },
            set: {
                ($0 as! T)[keyPath: keyPath] = V.init(fromValue: $1)
            })
    }

    static func accessor<T: Facet, V: RawRepresentable>(_ keyPath: ReferenceWritableKeyPath<T, V>) -> Accessor where V.RawValue == String {
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

   static func accessor<T: Facet>(_ keyPath: ReferenceWritableKeyPath<T, [Entity]>) -> Accessor {
        return Accessor(
            get: { .list(($0 as! T)[keyPath: keyPath].map { Value.entity($0) }) },
            set: { (object, value) in
                // FIXME: Not implemented
            })
    }
}
