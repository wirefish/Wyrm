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

    // Elemental and magical damage types.
    case fire, cold, electricity, acid, nature, magic

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

enum CombatTrait: Hashable, ValueRepresentableEnum {
    case power  // increases attack
    case protection  // increases defense
    case precision  // increases chance of critical hit
    case ferocity  // increases damage of critical hit
    case vitality  // increases maximum health
    case affinity(DamageType)  // increases attack and defense for one damage type

    // NOTE: Because affinity has an associated value, it is handled differently and
    // not included in allCases by design.
    
    static var allCases: [CombatTrait] = [
        .power, .protection, .precision, .ferocity, .vitality
    ]

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })

    static func fromValue(_ value: Value) -> CombatTrait? {
        guard case let .symbol(name) = value else {
            return nil
        }
        if let damageType = DamageType.names[name] {
            return .affinity(damageType)
        } else if let c = Self.names[name] {
            return c
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

    var description: String {
        if case let .affinity(damageType) = self {
            return "\(String(describing: damageType)) affinity"
        } else {
            return String(describing: self)
        }
    }
}

struct ScaledTrait: ValueRepresentable {
    let trait: CombatTrait
    let coeff: Double

    static func fromValue(_ value: Value) -> ScaledTrait? {
        guard case let .list(spec) = value,
              spec.values.count == 2,
              let trait = CombatTrait.fromValue(spec.values[0]),
              let coeff = Double.fromValue(spec.values[1]) else {
            return nil
        }
        return ScaledTrait(trait: trait, coeff: coeff)
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

extension Avatar {
    func computeTraits() -> [CombatTrait:Double] {
        // TODO: take race and auras into account
        var traits: [CombatTrait:Double] = [
            .power: Double(level + 1) * 10.0,
            .protection: Double(level + 1) * 10.0,
        ]
        for item in equipped.values {
            if let trait = item.trait {
                traits[trait, default: 0.0] += item.traitValue
            }
        }
        return traits
    }
}
