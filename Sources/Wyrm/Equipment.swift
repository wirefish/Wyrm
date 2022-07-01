//
//  Equipment.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum EquippableSlot: ValueRepresentableEnum {
    // Weapons and tools.
    case mainHand, offHand, eitherHand, bothHands

    // Clothing.
    case head, torso, hands, waist, legs, feet

    // Accessories.
    case ears, neck, wrists, eitherFinger

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

class Equipment: Item {
    var slot: EquippableSlot?
    var trait: CombatTrait?
    var traitCoeff = 1.0

    override func copyProperties(from other: Entity) {
        let other = other as! Equipment
        slot = other.slot
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "slot": accessor(\Equipment.slot),
        "trait": accessor(\Equipment.trait),
        "trait_coeff": accessor(\Equipment.traitCoeff),
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
