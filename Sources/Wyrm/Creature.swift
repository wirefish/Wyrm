//
//  Creature.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Creature: PhysicalEntity, Attackable {
    // Attackable
    var level = 1
    var currentHealth: Int = 1  // FIXME:
    var maxHealth: Int { return 10 + 10 * level }

    override func copyProperties(from other: Entity) {
        let other = other as! Creature
        level = other.level
        currentHealth = other.currentHealth
        super.copyProperties(from: other)
    }

    func defenseAgainst(damageType: DamageType) -> Int { 0 }
}
