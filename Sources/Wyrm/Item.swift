//
//  Item.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

class Item: PhysicalEntity {
    var stackLimit = 1
    var count = 1
    var level = 0
    var useVerbs = [String]()
    var quest: ValueRef?

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
        "stack_limit": accessor(\Item.stackLimit),
        "count": accessor(\Item.count),
        "level": accessor(\Item.level),
        "use_verbs": accessor(\Item.useVerbs),
        "quest": accessor(\Item.quest),
    ]

    override subscript(member: String) -> Value? {
        get { return Item.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Item.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }

    override func isVisible(to observer: Avatar) -> Bool {
        if let quest = quest, observer.activeQuests[quest] == nil {
            return false
        }
        return super.isVisible(to: observer)
    }

    override func canInsert(into container: Container) -> Bool {
        return container.size >= size
    }
}

extension Item: Encodable {
    enum CodingKeys: CodingKey {
        case prototype, count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prototype!.ref!, forKey: .prototype)
        try container.encode(count, forKey: .count)
    }
}
