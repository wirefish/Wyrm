//
//  Creature.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Creature: PhysicalEntity, Combatant, Questgiver {
    // Attackable
    var level = 1
    var health = ClampedInt(1, maxValue: 1)
    var minHealth = 0
    var attack_coeff = 1.0
    var defense_coeff = 1.0
    var health_coeff = 1.0
    var weapons = [Weapon]()

    // Questgiver
    var offersQuests = [Quest]()

    var sells: [ValueRef]?
    var teaches: [ValueRef]?

    override func copyProperties(from other: Entity) {
        let other = other as! Creature
        level = other.level
        attack_coeff = other.attack_coeff
        defense_coeff = other.defense_coeff
        health_coeff = other.health_coeff
        weapons = other.weapons
        offersQuests = other.offersQuests
        sells = other.sells
        teaches = other.teaches
        super.copyProperties(from: other)

        health.maxValue = Int(health_coeff * Double(baseHealth(level: level)))
        health.value = health.maxValue
    }

    private static let accessors = [
        "level": Accessor(\Creature.level),
        "min_health": Accessor(\Creature.minHealth),
        "attack_coeff": Accessor(\Creature.attack_coeff),
        "defense_coeff": Accessor(\Creature.defense_coeff),
        "health_coeff": Accessor(\Creature.health_coeff),
        "weapons": Accessor(\Creature.weapons),
        "offers_quests": Accessor(\Creature.offersQuests),
        "sells": Accessor(\Creature.sells),
        "teaches": Accessor(\Creature.teaches),
    ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }

    func defense(against damageType: DamageType) -> Int {
        0
    }

    func nextAttack(against target: Combatant) -> Attack? {
        nil
    }
}
