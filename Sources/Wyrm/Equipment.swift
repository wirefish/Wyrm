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

    // Storage.
    case backpack

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

class Equipment: Item {
    var slot: EquippableSlot?
    var trait: CombatTrait?
    var traitCoeff = 1.0

    // Inventory capacity gained by equipping this item.
    var capacity = 0

    override func copyProperties(from other: Entity) {
        let other = other as! Equipment
        slot = other.slot
        trait = other.trait
        traitCoeff = other.traitCoeff
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "slot": accessor(\Equipment.slot),
        "trait": accessor(\Equipment.trait),
        "trait_coeff": accessor(\Equipment.traitCoeff),
        "capacity": accessor(\Equipment.capacity),
    ]

    override subscript(member: String) -> Value? {
        get { return Self.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Self.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }
}

class Weapon: Equipment {
    var damageType = DamageType.crushing
    var speed = 3.0
    var attackVerb = "hits"
    var criticalVerb = "critically hits"

    override func copyProperties(from other: Entity) {
        let other = other as! Weapon
        damageType = other.damageType
        speed = other.speed
        attackVerb = other.attackVerb
        criticalVerb = other.criticalVerb
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "damage_type": accessor(\Weapon.damageType),
        "speed": accessor(\Weapon.speed),
        "attack_verb": accessor(\Weapon.attackVerb),
        "critical_verb": accessor(\Weapon.criticalVerb),
    ]

    override subscript(member: String) -> Value? {
        get { return Self.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Self.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }
}
