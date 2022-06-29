//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

// A reference to an entity may contain an explicit module name, in which case only that
// module is searched. Otherwise, the search uses the current module, and any imported modules,
// and the builtins module.
struct EntityRef: Equatable {
    let module: String?
    let name: String
}

class Entity: Observer, ValueDictionary, CustomDebugStringConvertible {
    let id = idIterator.next()!
    let prototype: Entity?
    var handlers = [EventHandler]()
    var extraMembers: [String:Value]

    static var idIterator = (1...).makeIterator()

    init(withPrototype prototype: Entity?) {
        self.prototype = prototype
        extraMembers = prototype?.extraMembers ?? [:]
    }

    func clone() -> Entity {
        return Entity(withPrototype: self)
    }

    subscript(memberName: String) -> Value? {
        get { return extraMembers[memberName] }
        set { extraMembers[memberName] = newValue }
    }

    func matchHandlers(observer: Entity, phase: EventPhase, event: String, args: [Value]) -> [EventHandler] {
        return matchHandlers(handlers: handlers, observer: observer, phase: phase,
                             event: event, args: args) +
            (prototype?.matchHandlers(observer: observer, phase: phase, event: event, args: args) ?? [])
    }

    func addHandler(_ handler: EventHandler) {
        handlers.append(handler)
    }

    var debugDescription: String { "<\(type(of: self)) id=\(id)>" }
}
