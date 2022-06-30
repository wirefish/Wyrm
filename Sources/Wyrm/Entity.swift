//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class Entity: Observer, ValueDictionary, CustomDebugStringConvertible {
    static var idIterator = (1...).makeIterator()

    let id = idIterator.next()!
    var ref: ValueRef?
    let prototype: Entity?
    var handlers = [EventHandler]()
    var extraMembers = [String:Value]()

    required init(withPrototype prototype: Entity?) {
        self.prototype = prototype
    }

    func copyProperties(from other: Entity) {
        extraMembers = other.extraMembers
    }

    func copy() -> Self {
        let entity = Self.init(withPrototype: self.prototype)
        entity.copyProperties(from: self)
        return entity
    }

    func extend() -> Self {
        assert(self.ref != nil, "cannot extend anonymous entity")
        let entity = Self.init(withPrototype: self)
        entity.copyProperties(from: self)
        return entity
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

    override func copyProperties(from other: Entity) {
        let other = other as! PhysicalEntity
        brief = other.brief
        pose = other.pose
        description = other.description
        icon = other.icon
        super.copyProperties(from: other)
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
