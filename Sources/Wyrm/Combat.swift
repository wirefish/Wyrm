//
//  Combat.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

enum DamageType {
    // Physical damage types.
    case crushing, piercing, slashing

    // Elemental damage types.
    case fire, cold, electricity, acid
}

protocol Attackable {
    var level: Int { get }
    var currentHealth: Int { get set }
    var maxHealth: Int { get }

    func defenseAgainst(damageType: DamageType) -> Int
}
