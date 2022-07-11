//
//  PhysicalEntity.swift
//  Wyrm
//

class PhysicalEntity: Entity, Viewable, Matchable {
    var brief: NounPhrase?
    var pose: String?
    var description: String?
    var icon: String?
    var isObvious = true
    var alts = [NounPhrase]()
    weak var container: Container?

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

    // MARK: - Viewable

    func isVisible(to observer: Avatar) -> Bool {
        return true
    }

    func isObvious(to observer: Avatar) -> Bool {
        return isObvious
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
