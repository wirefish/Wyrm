//
//  Item.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

class Item: Entity, Viewable, Matchable {
    // Viewable
    var brief: NounPhrase?
    var pose: VerbPhrase?
    var description: String?
    var icon: String?

    // Matchable
    var alts = [NounPhrase]()

    var size = Size.small
    var level = 0
    var useVerbs = [String]()

    required init(withPrototype prototype: Item?) {
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        return Item(withPrototype: self)
    }

    static let accessors = [
        "brief": accessor(\Item.brief),
        "pose": accessor(\Item.pose),
        "description": accessor(\Item.description),
        "icon": accessor(\Item.icon),
        "alts": accessor(\Item.alts),
        "size": accessor(\Item.size),
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
}
