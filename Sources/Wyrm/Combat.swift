//
//  Combat.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

import Foundation

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
    case affinity(DamageType)  // increases attack and defense for one damage type

    // NOTE: Because affinity has an associated value, it is handled differently and
    
    static var allCases: [CombatTrait] = [
        .power, .protection, .precision, .ferocity, .vitality
    ]

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })

    init?(fromValue value: Value) {
        guard case let .symbol(name) = value else {
            return nil
        }
        if let damageType = DamageType.names[name] {
            self = .affinity(damageType)
        } else if let c = Self.names[name] {
            self = c
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        switch self {
        case let .affinity(damageType):
            return damageType.toValue()
        default:
            return .symbol(String(describing: self))
        }
    }
}

struct ScaledTrait {
    let trait: CombatTrait
    let coeff: Double

    init?(fromValue value: Value) {
        guard case let .list(spec) = value,
              spec.values.count == 2,
              let trait = CombatTrait(fromValue: spec.values[0]),
              let coeff = Double.fromValue(spec.values[1]) else {
            return nil
        }
        self.trait = trait
        self.coeff = coeff
    }

    func toValue() -> Value {
        .list(ValueList([trait.toValue(), coeff.toValue()]))
    }
}

protocol Attackable {
    var level: Int { get }
    var currentHealth: Int { get set }
    var maxHealth: Int { get }

    func defenseAgainst(damageType: DamageType) -> Int
}

fileprivate let healthBase = pow(2.5, 0.1)

func computeMaxHealth(level: Int, healthCoeff: Double = 1.0) -> Int {
    Int(100.0 * (0.25 * Double(level) + pow(healthBase, Double(level - 1))) * healthCoeff)
}
