//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class Entity: Observer, ValueDictionary, CustomDebugStringConvertible {
    let id = idIterator.next()!
    var ref: ValueRef?
    let prototype: Entity?
    var handlers = [EventHandler]()
    var extraMembers: [String:Value]

    static var idIterator = (1...).makeIterator()

    init(withPrototype prototype: Entity?) {
        self.prototype = prototype
        extraMembers = prototype?.extraMembers ?? [:]
    }

    func clone() -> Entity {
        assert(ref != nil)
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

    var debugDescription: String {
        if let ref = ref {
            return "<\(type(of: self)) ref=\(ref)>"
        } else if let protoRef = prototype?.ref {
            return "<\(type(of: self)) id=\(id) proto=\(protoRef)>"
        } else {
            return "<\(type(of: self)) id=\(id) proto=??>"
        }
    }
}

class PhysicalEntity: Entity, Viewable, Matchable {
    // Viewable
    var brief: NounPhrase?
    var pose: VerbPhrase?
    var description: String?
    var icon: String?

    // Matchable
    var alts = [NounPhrase]()

    init(withPrototype prototype: PhysicalEntity?) {
        if let prototype = prototype {
            brief = prototype.brief
            pose = prototype.pose
            description = prototype.description
            icon = prototype.icon
        }
        super.init(withPrototype: prototype)
    }

    private static let accessors = [
        "brief": accessor(\PhysicalEntity.brief),
        "pose": accessor(\PhysicalEntity.pose),
        "description": accessor(\PhysicalEntity.description),
        "icon": accessor(\PhysicalEntity.icon),
        "alts": accessor(\PhysicalEntity.alts),
    ]

    override subscript(member: String) -> Value? {
        get { return PhysicalEntity.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = PhysicalEntity.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }
}
