//
//  Item.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

class Item: PhysicalEntity, Encodable {
    var size = Size.small
    var stackLimit = 1
    var count = 1
    var level = 0
    var useVerbs = [String]()

    init(withPrototype prototype: Item?) {
        if let prototype = prototype {
            size = prototype.size
            stackLimit = prototype.stackLimit
            count = prototype.count
            level = prototype.level
            useVerbs = prototype.useVerbs
        }
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        return Item(withPrototype: self)
    }

    private static let accessors = [
        "size": accessor(\Item.size),
        "stack_limit": accessor(\Item.stackLimit),
        "count": accessor(\Item.count),
        "level": accessor(\Item.level),
        "use_verbs": accessor(\Item.useVerbs),
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

    enum CodingKeys: CodingKey {
        case prototype, count
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(prototype!.ref!, forKey: .prototype)
        try container.encode(count, forKey: .count)
    }
}