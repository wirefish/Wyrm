//
//  Entity.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

class Entity: ValueDictionary {
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

    // Creates a new entity of the same type with a copy of this entity's properties.
    // If this is a "named" entity (i.e. one defined at the top level of a script file
    // and therefore with a non-nil ref), then the new entity uses this entity as its
    // prototype. Otherwise, the new entity shares a prototype with this entity.
    final func clone() -> Self {
        let prototype = self.ref == nil ? self.prototype : self
        let entity = Self.init(withPrototype: prototype)
        entity.copyProperties(from: self)
        return entity
    }

    final func extends(_ ref: ValueRef) -> Bool {
        return ref == self.ref || (prototype?.extends(ref) ?? false)
    }

    // This will be overridden by subclasses which must always call their superclass
    // method if they don't define the member themselves.
    subscript(memberName: String) -> Value? {
        get { return extraMembers[memberName] }
        set { extraMembers[memberName] = newValue }
    }
}

extension Entity: Hashable {
    static func == (_ lhs: Entity, _ rhs: Entity) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Entity: CustomDebugStringConvertible {
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

extension Entity {
    @discardableResult
    final func handleEvent(_ phase: EventPhase, _ event: String, args: [Value]) -> Value {
        var observer: Entity! = self
        while observer != nil {
            let args = [.entity(observer)] + args
            let handlers = observer.handlers.keep {
                $0.appliesTo(phase: phase, event: event, observer: self, args: args)
            }
            // FIXME: handle fallthrough
            if let handler = handlers.first {
                do {
                    return try handler.fn.call(args, context: [observer]) ?? .nil
                } catch {
                    logger.error("error executing event handler: \(error)")
                    return .nil
                }
            }
            observer = observer.prototype
        }
        return .nil
    }

    final func allowEvent(_ event: String, args: [Value]) -> Bool {
        return handleEvent(.allow, event, args: args) != .boolean(false)
    }
}

class PhysicalEntity: Entity, Viewable, Matchable {
    // Viewable
    var brief: NounPhrase?
    var pose: String?
    var description: String?
    var icon: String?
    var isObvious = true

    // Matchable
    var alts = [NounPhrase]()

    var container: Container?

    override func copyProperties(from other: Entity) {
        let other = other as! PhysicalEntity
        brief = other.brief
        pose = other.pose
        description = other.description
        icon = other.icon
        isObvious = other.isObvious
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "brief": accessor(\PhysicalEntity.brief),
        "pose": accessor(\PhysicalEntity.pose),
        "description": accessor(\PhysicalEntity.description),
        "icon": accessor(\PhysicalEntity.icon),
        "is_obvious": accessor(\PhysicalEntity.isObvious),
        "alts": accessor(\PhysicalEntity.alts),
    ]

    override subscript(member: String) -> Value? {
        get { Self.accessors[member]?.get(self) ?? super[member] }
        set {
            if Self.accessors[member]?.set(self, newValue!) == nil {
                super[member] = newValue
            }
        }
    }

    static let defaultBrief = NounPhrase("an entity")
    static let defaultPose = "is here."

    func describePose() -> String {
        let brief = brief ?? Self.defaultBrief
        return "\(brief.format(capitalize: true)) \(pose ?? Self.defaultPose)"
    }
}
