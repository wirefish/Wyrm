//
//  PhysicalEntity.swift
//  Wyrm
//

class PhysicalEntity: Entity, Viewable, Matchable {
    // Viewable
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

    static let defaultBrief = NounPhrase("an entity")
    static let defaultPose = "is here."

    func describePose() -> String {
        let brief = brief ?? Self.defaultBrief
        return "\(brief.format(capitalize: true)) \(pose ?? Self.defaultPose)"
    }

    func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return alts.reduce(brief?.match(tokens) ?? .none) { max($0, $1.match(tokens)) }
    }
}
