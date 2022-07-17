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
    var attack_coeff = 1.0
    var defense_coeff = 1.0
    var health_coeff = 1.0
    var weapons = [Weapon]()

    // Questgiver
    var offersQuests = [Quest]()

    override func copyProperties(from other: Entity) {
        let other = other as! Creature
        level = other.level
        attack_coeff = other.attack_coeff
        defense_coeff = other.defense_coeff
        health_coeff = other.health_coeff
        weapons = other.weapons
        offersQuests = other.offersQuests
        super.copyProperties(from: other)

        health.maxValue = Int(health_coeff * Double(baseHealth(level: level)))
        health.value = health.maxValue
    }

    private static let accessors = [
        "level": accessor(\Creature.level),
        "attack_coeff": accessor(\Creature.attack_coeff),
        "defense_coeff": accessor(\Creature.defense_coeff),
        "health_coeff": accessor(\Creature.health_coeff),
        "weapons": accessor(\Creature.weapons),
        "offers_quests": accessor(\Creature.offersQuests),
    ]

    override subscript(member: String) -> Value? {
        get { return Creature.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Creature.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }

    func defense(against damageType: DamageType) -> Int {
        0
    }

    func nextAttack(against target: Combatant) -> Attack? {
        nil
    }
}
