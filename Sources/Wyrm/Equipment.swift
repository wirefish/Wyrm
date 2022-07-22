//
//  Equipment.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum EquipmentSlot: String, CodingKeyRepresentable, Hashable, Codable, ValueRepresentableEnum {
    // Weapons and tools.
    case mainHand, offHand, tool

    // Clothing.
    case head, torso, back, hands, waist, legs, feet

    // Accessories.
    case ears, neck, leftWrist, rightWrist, leftFinger, rightFinger, trinket

    // Storage.
    case backpack, beltPouch

    // Meta-slots.
    case bothHands, eitherHand, eitherWrist, eitherFinger

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })

    var coeff: Double {
        switch self {
        case .mainHand: return 1.0
        case .offHand: return 1.0
        case .tool: return 1.0

        case .head: return 0.6
        case .torso: return 1.0
        case .back: return 0.5
        case .hands: return 0.5
        case .waist: return 0.4
        case .legs: return 1.0
        case .feet: return 0.5

        case .ears: return 0.5
        case .neck: return 0.5
        case .leftWrist: return 0.25
        case .rightWrist: return 0.25
        case .leftFinger: return 0.25
        case .rightFinger: return 0.25
        case .trinket: return 0.5

        case .backpack: return 1.0
        case .beltPouch: return 0.5

        case .bothHands: return 2.0
        case .eitherHand: return 1.0
        case .eitherWrist: return 0.25
        case .eitherFinger: return 0.25
        }
    }

    var defenseCoeff: Double {
        switch self {
        case .head, .torso, .back, .hands, .waist, .legs, .feet: return coeff
        default: return 0.0
        }
    }
}

enum EquipmentQuality: Encodable, Comparable, ValueRepresentableEnum {
    case poor, normal, good, excellent, legendary

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })

    var coeff: Double {
        switch self {
        case .poor: return 0.75
        case .normal: return 1.0
        case .good: return 1.25
        case .excellent: return 1.5
        case .legendary: return 1.75
        }
    }
}

class Equipment: Item {
    var slot: EquipmentSlot?
    var quality: EquipmentQuality = .normal
    var trait: CombatTrait?

    // Inventory capacity gained by equipping this item.
    var capacity = 0

    override func copyProperties(from other: Entity) {
        let other = other as! Equipment
        slot = other.slot
        quality = other.quality
        trait = other.trait
        capacity = other.capacity
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "slot": Accessor(\Equipment.slot),
        "quality": Accessor(\Equipment.quality),
        "trait": Accessor(\Equipment.trait),
        "capacity": Accessor(\Equipment.capacity),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    var traitValue: Double {
        Double(level) * 10.0 * quality.coeff * slot!.coeff
    }

    override func descriptionNotes() -> [String] {
        var notes = super.descriptionNotes()
        if quality != .normal {
            notes.append("Quality: \(String(describing: quality)).")
        }
        if let trait = trait {
            notes.append(String(format: "Trait: %@ +%1.1f.", trait.description, traitValue))
        }
        return notes
    }

}

class Weapon: Equipment {
    var damageType = DamageType.crushing
    var speed = 3.0
    var variance = 0.2
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
        "damageType": Accessor(\Weapon.damageType),
        "speed": Accessor(\Weapon.speed),
        "variance": Accessor(\Weapon.variance),
        "attackVerb": Accessor(\Weapon.attackVerb),
        "criticalVerb": Accessor(\Weapon.criticalVerb),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    var attackValue: Double {
        Double(level + (slot == .bothHands ? 1 : 0)) * 20.0
    }

    override func descriptionNotes() -> [String] {
        var notes = super.descriptionNotes()
        notes.append(String(format: "Attack: %1.1f.", attackValue))
        return notes
    }
}
