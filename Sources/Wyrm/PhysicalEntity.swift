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
    var size = Size.huge
    weak var container: Entity?

    override func copyProperties(from other: Entity) {
        let other = other as! PhysicalEntity
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
        "brief": accessor(\PhysicalEntity.brief),
        "pose": accessor(\PhysicalEntity.pose),
        "description": accessor(\PhysicalEntity.description),
        "icon": accessor(\PhysicalEntity.icon),
        "is_obvious": accessor(\PhysicalEntity.isObvious),
        "alts": accessor(\PhysicalEntity.alts),
        "size": accessor(\PhysicalEntity.size),
        "location": accessor(\PhysicalEntity.location),
    ]

    override subscript(member: String) -> Value? {
        get { Self.accessors[member]?.get(self) ?? super[member] }
        set {
            if Self.accessors[member]?.set(self, newValue!) == nil {
                super[member] = newValue
            }
        }
    }

    var location: Location {
        get { container as! Location }
        set { container = newValue }
    }

    // MARK: - Viewable

    func isVisible(to observer: Avatar) -> Bool {
        return true
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

    // MARK: - inserting into a container

    func canInsert(into container: Container) -> Bool {
        return false
    }

    func canMerge(into stack: PhysicalEntity) -> Bool {
        return false
    }
}
