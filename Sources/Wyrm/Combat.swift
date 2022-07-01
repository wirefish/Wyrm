//
//  Combat.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

enum DamageType: ValueRepresentableEnum {
    // Physical damage types.
    case crushing, piercing, slashing

    // Elemental damage types.
    case fire, cold, electricity, acid

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

enum CombatTrait: ValueRepresentableEnum {
    case power  // increases attack
    case protection  // increases defense
    case precision  // increases chance of critical hit
    case ferocity  // increases damage of critical hit
    case vitality  // increases maximum health
    // FIXME: case affinity(DamageType)  // increases attack and defense for one damage type

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

protocol Attackable {
    var level: Int { get }
    var currentHealth: Int { get set }
    var maxHealth: Int { get }

    func defenseAgainst(damageType: DamageType) -> Int
}
