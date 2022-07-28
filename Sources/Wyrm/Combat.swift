//
//  Combat.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

import Foundation
import AppKit

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

struct ClampedInt {
    private var value_: Int

    init(_ value: Int, maxValue: Int) {
        self.maxValue = maxValue
        value_ = Self.clamped(value, maxValue)
    }

    var maxValue: Int {
        didSet { value_ = Self.clamped(value_, maxValue) }
    }

    var value: Int {
        get { return value_ }
        set { value_ = Self.clamped(newValue, maxValue) }
    }

    private static func clamped(_ value: Int, _ maxValue: Int) -> Int {
        max(0, min(value, maxValue))
    }
}

struct Attack {
    let delay: Double
    let power: Double
    let weapon: Weapon
}

protocol Combatant: AnyObject {
    var level: Int { get }
    var health: ClampedInt { get set }

    func defense(against damageType: DamageType) -> Int

    func nextAttack(against target: Combatant) -> Attack?
}

extension Combatant {
    // Base XP awarded for killing a combatant based on its level. This can be
    // reduced if the killer's level is higher.
    func xpValue() -> Int {
        30 + 5 * level
    }
}

extension Avatar {
    // Returns a dictionary containing all of the avatar's combat trait values,
    // taking into account all modifiers from race, auras, and equipment.
    func computeTraits() -> [CombatTrait:Double] {
        // Base values derived from level.
        var traits: [CombatTrait:Double] = [
            .power: Double(level + 1) * 10.0,
            .protection: Double(level + 1) * 10.0,
        ]
        // Add values from equipment.
        for item in equipped.values {
            if let trait = item.trait {
                traits[trait, default: 0.0] += item.traitValue
            }
        }
        // TODO: take race and auras into account
        return traits
    }
}

// MARK: - core calculations

// The effective attack rating considering the attacker's attack rating and the
// defender's defense rating.
func effectiveAttack(attack: Double, defense: Double) -> Double {
    attack * (1.0 + (attack - defense) / (attack + defense))
}

// The base attack and/or defense rating of an entity based on its level.
func baseRating(level: Int) -> Double {
    Double(100 + (level - 1) * level)
}

func baseHealth(level: Int) -> Int {
    return Int((baseRating(level: level) * 1.5).rounded())
}

extension Double {
    func roundedRandomly() -> Double {
        let k = self.truncatingRemainder(dividingBy: 1.0)
        return self.rounded(Double.random(in: 0..<1) < k ? .up : .down)
    }
}

func damage(effectiveAttack: Double, weapon: Weapon) -> Int {
    let c = effectiveAttack * weapon.quality.coeff * (weapon.speed / 3.0)
    let v = c * weapon.variance
    return Int((0.1 * Double.random(in: (c - v)...(c + v))).roundedRandomly())
}

// MARK: - attack command

// FIXME: This is a placeholder just to allow quest advancement.
class Combat: Activity {
    let name = "in combat"  // FIXME: with ...
    weak var avatar: Avatar?
    weak var target: Creature?
    let duration: Double

    init(_ avatar: Avatar, _ target: Creature, duration: Double = 2.0) {
        self.avatar = avatar
        self.target = target
        self.duration = duration
    }

    func begin() {
        if let avatar = avatar, let target = target {
            avatar.show("You begin attacking \(target.describeBriefly([.definite])).")
            World.schedule(delay: duration) { self.finish() }
        } else {
            finish()
        }
    }

    func cancel() {
        if let avatar = self.avatar {
            avatar.show("You stop attacking.")
        }
        self.avatar = nil
    }

    func finish() {
        if let avatar = avatar {
            if let target = target {
                // FIXME: default weapon?
                let weapon = avatar.equipped[.mainHand]!
                triggerEvent("kill", in: avatar.location, participants: [avatar, target, weapon],
                             args: [avatar, target, weapon]) {
                    avatar.showNotice("You killed \(target.describeBriefly([.definite]))!")

                    // FIXME: award experience for all combatants
                    avatar.gainXP(target.xpValue())

                    // FIXME: drop loot for all combatants

                    // FIXME: exit_location or exit_world event
                    avatar.location.remove(target)
                }
            }
            avatar.activityFinished()
        }
    }
}

let attackCommand = Command("attack target") {
    actor, verb, clauses in
    if case let .tokens(target) = clauses[0] {
        guard let matches = match(target, against: actor.location.contents, where: {
            $0 is Creature && $0.isVisible(to: actor) }) else {
            actor.show("You don't see anything like that to attack.")
            return
        }
        if matches.count > 1 {
            actor.show("Do you want to attack \(matches.describe(using: "or"))?")
            return
        }

        actor.beginActivity(Combat(actor, matches.first! as! Creature))
    } else {
        actor.show("What do you want to attack?")
    }
}
