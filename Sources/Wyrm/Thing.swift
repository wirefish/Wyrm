//
//  Thing.swift
//  Wyrm
//

class Thing: Entity, Viewable, Matchable {
    var brief: NounPhrase?
    var pose: String?
    var description: String?
    var icon: String?
    var isObvious = true
    var alts = [NounPhrase]()
    var size = Size.huge
    weak var container: Entity?

    override func copyProperties(from other: Entity) {
        let other = other as! Thing
        brief = other.brief
        pose = other.pose
        description = other.description
        icon = other.icon
        isObvious = other.isObvious
        alts = other.alts
        size = other.size
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "brief": Accessor(\Thing.brief),
        "pose": Accessor(\Thing.pose),
        "description": Accessor(\Thing.description),
        "icon": Accessor(\Thing.icon),
        "isObvious": Accessor(\Thing.isObvious),  // FIXME: -> implied
        "alts": Accessor(\Thing.alts),
        "size": Accessor(\Thing.size),
        "location": Accessor(\Thing.location),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    var location: Location {
        get { container as! Location }
        set { container = newValue }
    }

    // MARK: - Viewable

    func isVisible(to observer: Avatar) -> Bool {
        if case let .function(fn) = self.get("visible"),
           case let .value(value) = try? fn.call([.entity(self), .entity(observer)], context: [self]),
           case let .boolean(visible) = value {
            return visible
        } else {
            return true
        }
    }

    func isObvious(to observer: Avatar) -> Bool {
        return isObvious && isVisible(to: observer)
    }

    static let defaultBrief = NounPhrase("an entity")

    func describeBriefly(_ format: Text.Format) -> String {
        return (brief ?? Self.defaultBrief).format(format)
    }

    func describePose() -> String {
        return pose ?? "is here."
    }

    func describeFully() -> String {
        return description ?? "The entity is unremarkable."
    }

    // MARK: - Matchable

    func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return alts.reduce(brief?.match(tokens) ?? .none) { max($0, $1.match(tokens)) }
    }
}
