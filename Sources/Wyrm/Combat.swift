//
//  Combat.swift
//  Wyrm
//

import Darwin

/*

 NOTES:

 The goal is to keep things simple.

 An attack is an opposed roll between an attacker and defender. Each has an effective
 level which is used to modifier their roll.

 For an attacker, effective level is actualLevel + attackLevel + power + affinity.
 AttackLevel is the level of the weapon or spell. For natural weapons it is equal to
 actualLevel. Power and affinity are a combat traits.

 For a defender, effective level is actualLevel + armorLevel + protection + resistance.
 ArmorLevel is the weighted average level of any equipped armor pieces. For most creatures
 it is equal to actualLevel. Protection and resistance are combat traits. Note that
 resistance can be negative (becoming a vulnerability).

 Combat traits are values derived from armor, race, or auras. They may also be inherent.

 Each rolls 1...20 and adds their effective level. If the attacker rolls A and the defender
 rolls D, then A - D determines the success of the attack:

 A = D: "normal" success (1.0x normal damage)

 A > D: more success, scaling up to 1.5x damage at A - D = 20.

 A < D: less success, scaling down to 0.5x damage at D - A = 20.

 A + 20 < D: miss

 critical chance and multiplier apply to damage only if A >= D.

 Normal damage is calculated using a base damage associated with the attack, scaled based
 on attackLevel.

 Creature
  +- Combatant (can equip, have auras, have race, inherent traits, attitude)
  |   +- Avatar
  +- Questgiver
  +- Vendor

 Combat overall is pretty simple.

 Every combatant has base attack and defense values that increase with
 level.

 Some equipment has direct attack and defense values as well:

 A weapon has inherent attack based on its level, quality, and average dps
 (computed from its speed and base damage).

 Armor and shields have inherent defense based on their level, quality, type
 (i.e. light, medium, or heavy) and slot.

 If a combatant wields multiple weapons, only the weapon being used for an
 attack contributes its attack value.

 Attack and defense values can also be modified by affixes (on equipment or
 auras), e.g. a power affix increases attack and a protection affix increases
 defense.

 An affix adjusts the combatant's effective level. The effective level is then
 used to compute attack or defense.

 Each point of affix's strength just adds some constant to the effective level.
 The constant is a tunable scale factor. So a "protection +3" affix would add 3
 * K to the effective level used to compute defense.

 In addition, for a specific damage type, attack and defense are modified by
 affinity and resistance affixes associated with that type.

 The strength of an affix generally depends on the level of its source, e.g.
 item level or spell level. Skill-based "innate" affixes depend on combatant
 level. Item-based affixes can also be weighted by equipment slot, e.g. chest
 armor provides more than a belt. But this is up to the designer and not
 constrained by the engine.

 Every attack (spell, weapon, etc) has a base damage and a variance (as a
 percentage). Actual rolled damage is a random value chosen from the closed
 range [base * (1 - var), base * (1 + var)].

 Modify attack and defense from all sources then compute (att - def) / def.
 Apply diminishing returns. This is the multiplier applied to the rolled damage.

 Critical hits: the above value can be modified if a crit is scored, based on
 the attacker's precision and vitality affixes.

 A shield has a block value. It can randomly block a percentage of the
 incoming damage, if the damage type is blockable.

 Final damage is a "randomly rounded" integer computed from the above. E.g. 6.3
 damage has a 70% chance to be 6 and a 30% chance to be 7.

 */

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
  // Each point of power increases attack rating by 0.1.
  case power

  // Each point of protection increases defense rating by 0.1.
  case protection

  // Each point of precision increases critical hit chance by 0.2%.
  case precision  // increases chance of critical hit

  // Each point of ferocity increases critical hit damage by 1%.
  case ferocity  // increases damage of critical hit

  // Each point of vitality increases maximum health by 1%.
  case vitality

  // Each point of affinity increases attack rating by 0.1 for relevant attacks.
  case affinity(DamageType)

  // Each point of resistance increases defense rating by 0.1 for relevant attacks.
  // Note that resistance can be negative (to model a vulnerability).
  case resistance(DamageType)

  // NOTE: Because affinity and resistance have an associated value, they are
  // handled differently and not included in allCases by design.
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

// MARK: Attack

struct Attack {
  // The level of the attack.
  var level = 1

  // The type of damage done.
  var damageType = DamageType.crushing

  // The base amount of damage done.
  var damage: ClosedRange<Int> = 1...2

  // The base amount of time required to perform the attack, in seconds.
  var speed = 3.0

  // If non-zero, the number of times the damage is applied. Each application occurs
  // after a set delay.
  var ticks = 0

  // The verb used to describe the attack.
  var verb = "hits"

  // The verb used to describe a critical hit with the attack.
  var criticalVerb = "critically hits"
}

// MARK: Combatant

enum Attitude: ValueRepresentableEnum {
  // Cannot be attacked by player and will not attack player.
  case friendly

  // Can be attacked but will not attack until provoked.
  case neutral

  // Can be attacked and will attack without provocation.
  case hostile

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })
}

protocol Combatant: AnyObject {
  // The combatant's level controls its overall strength in combat.
  var level: Int { get }

  // The current health of the combatant. Death occurs when health reaches zero.
  var health: Int { get }

  // The health at which the combatant is considered defeated. A value above zero
  // means that defeat subdues the combatant rather than killing it.
  var minHealth: Int { get }

  // The attitude of the combatant toward players.
  var attitude: Attitude { get }

  // A description of next attack the combatant will use against a target.
  func nextAttack(against target: Combatant) -> Attack?

  // The values of all combat traits for the combatant, merged from all possible sources:
  // equipment, auras, race, skills, inherent traits, etc.
  var combatTraits: [CombatTrait:Int] { get }

  // Items equipped by the combatant.
  var equipped: [EquipmentSlot:Equipment] { get }

  // TODO: add auras
}

extension Combatant {
  func attackRating(_ attack: Attack) -> Double {
    Double(level + attack.level) +
    Double(combatTraits[.power, default: 0]) * 0.1 +
    Double(combatTraits[.affinity(attack.damageType), default: 0]) * 0.1
  }

  func armorLevel() -> Double {
    equipped.reduce(0.0) { (partial, entry) in
      let (slot, item) = entry
      return partial + Double(item.effectiveLevel) * slot.armorMultiplier * item.armorMultiplier
    }
  }

  func defenseRating(_ attack: Attack) -> Double {
    Double(level) + armorLevel() +
    Double(combatTraits[.protection, default: 0]) * 0.1 +
    Double(combatTraits[.resistance(attack.damageType), default: 0]) * 0.1
  }

  func maxHealth() -> Int {
    let base = Double(10 * (level + 1))
    let modifier = 1.0 + Double(combatTraits[.vitality, default: 0]) * 0.01
    return max(1, Int((base * modifier).rounded()))
  }

  func criticalChance() -> Double {
    0.05 + Double(combatTraits[.precision, default: 0]) * 0.002
  }

  func criticalDamageMultiplier() -> Double {
    1.5 + Double(combatTraits[.ferocity, default: 0]) * 0.01
  }

  // Base XP awarded for killing a combatant based on its level. This can be
  // reduced if the killer's level is higher.
  func xpValue() -> Int {
    30 + 5 * level
  }
}

func scaleRange(_ range: ClosedRange<Int>, by x: Double) -> ClosedRange<Double> {
  Double(range.lowerBound) * x ... Double(range.upperBound) * x
}

// Returns the total damage done (if any) and a flag that is true if the attack was a
// critical hit.
func resolveAttack(attacker: Combatant, defender: Combatant, attack: Attack) -> (Int, Bool) {
  let att = attacker.attackRating(attack)
  let def = defender.defenseRating(attack)

  // The attack effectivness is a value in 0...2 determined by the relative attack
  // and defense ratings.
  let x = att - def + Double.random(in: -3...3)
  let eff = tanh(x * 0.1) + 1.0

  // The damage scales based on effectiveness and the attacker and attack level.
  let scale = eff * (1.0 + 0.25 * Double(attacker.level + attack.level - 2))
  var damage = Double.random(in: scaleRange(attack.damage, by: scale))

  // Check for a critical hit.
  var critical = false
  if damage > 0 {
    critical = Double.random(in: 0..<1) < attacker.criticalChance()
    if critical {
      damage *= attacker.criticalDamageMultiplier()
    }
  }

  return (Int(damage.roundedRandomly()), critical)
}

extension Avatar {
  // Returns a dictionary containing all of the avatar's combat trait values,
  // taking into account all modifiers from race, auras, and equipment.
  func computeTraits() -> [CombatTrait:Int] {
    // Add values from equipment.
    var traits = [CombatTrait:Int]()
    for item in equipped.values {
      traits.merge(item.traits) { $0 + $1 }
    }
    // TODO: take race and auras into account
    return traits
  }
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
