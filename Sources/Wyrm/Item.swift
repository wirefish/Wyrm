//
//  Item.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

// FIXME:
enum CodingError: Error {
    case badPrototype
}

class Item: PhysicalEntity, Codable {
    // If zero, this item cannot stack with other items inside a container and
    // the container can contain more than one item with the same prototype. If
    // positive, the item can stack with other items with the same prototype and
    // a container can contain at most one such stack.
    var stackLimit = 0

    // The number of items stacked together.
    var count = 1
    
    var level = 0
    var useVerbs = [String]()
    var quest: Ref?
    var price: Item?

    override func copyProperties(from other: Entity) {
        let other = other as! Item
        stackLimit = other.stackLimit
        count = other.count
        level = other.level
        useVerbs = other.useVerbs
        quest = other.quest
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "stackLimit": Accessor(\Item.stackLimit),
        "count": Accessor(\Item.count),
        "level": Accessor(\Item.level),
        "useVerbs": Accessor(\Item.useVerbs),
        "quest": Accessor(\Item.quest),
        "price": Accessor(\Item.price),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    override func isVisible(to observer: Avatar) -> Bool {
        if let quest = quest, observer.activeQuests[quest] == nil {
            return false
        }
        return super.isVisible(to: observer)
    }

    override func describeBriefly(_ format: Text.Format) -> String {
        return (brief ?? Self.defaultBrief).format(format, count: count)
    }

    func descriptionNotes() -> [String] {
        var notes = [String]()
        if self.quest != nil, case let .quest(quest) = world.lookup(self.quest!) {
            notes.append("Quest: \(quest.name).")
        }
        if level > 0 {
            notes.append("Level: \(level).")
        }
        return notes
    }

    override func describeFully() -> String {
        let base = super.describeFully()
        let notes = descriptionNotes()
        if notes.isEmpty {
            return base
        } else {
            return "\(base) (\(notes.joined(separator: " ")))"
        }
    }

    func isStackable(with stack: Item) -> Bool {
        return stackLimit > 0 && prototype == stack.prototype
    }

    override func canInsert(into container: Container) -> Bool {
        return container.size >= size
    }

    enum CodingKeys: CodingKey {
        case prototype, count
    }

    required convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let protoRef = try c.decode(Ref.self, forKey: .prototype)
        guard let proto = World.instance.lookup(protoRef)?.asEntity(Item.self) else {
            throw CodingError.badPrototype
        }
        self.init(withPrototype: proto)
        copyProperties(from: proto)

        self.count = try c.decode(Int.self, forKey: .count)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(prototype!.ref!, forKey: .prototype)
        try c.encode(count, forKey: .count)
    }
}
