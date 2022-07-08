//
//  Creature.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Creature: PhysicalEntity, Attackable, Questgiver {
    // Attackable
    var level = 1
    var currentHealth: Int = 1  // FIXME:
    var maxHealth: Int { return 10 + 10 * level }

    // Questgiver
    var offersQuests = [Quest]()

    override func copyProperties(from other: Entity) {
        let other = other as! Creature
        level = other.level
        currentHealth = other.currentHealth
        offersQuests = other.offersQuests
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "level": accessor(\Creature.level),
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

    func defenseAgainst(damageType: DamageType) -> Int { 0 }
}
