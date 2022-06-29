//
//  Equipment.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum EquippableSlot: CaseIterable, ValueRepresentable {
    // Weapons and tools.
    case mainHand, offHand, eitherHand, bothHands

    // Clothing.
    case head, torso, hands, waist, legs, feet

    // Accessories.
    case ears, neck, wrists, eitherFinger

    static let names = Dictionary(uniqueKeysWithValues: EquippableSlot.allCases.map {
        (String(describing: $0), $0)
    })

    init?(fromValue value: Value) {
        if let v = EquippableSlot.enumCase(fromValue: value, names: EquippableSlot.names) {
            self = v
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        return .symbol(String(describing: self))
    }
}

class Equipment: Item {
    var slot: EquippableSlot?

    init(withPrototype prototype: Equipment?) {
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        return Equipment(withPrototype: self)
    }

    private static let accessors = [
        "slot": accessor(\Equipment.slot),
    ]

    override subscript(member: String) -> Value? {
        get { return Equipment.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Equipment.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }
}
