//
//  Combat.swift
//  Wyrm
//

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
  case power  // increases attack
  case protection  // increases defense
  case precision  // increases chance of critical hit
  case ferocity  // increases damage of critical hit
  case vitality  // increases maximum health
  case affinity(DamageType)  // increases attack for one damage type
  case resistance(DamageType)  // increases defense for one damage type

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

struct ScaledTrait: ValueRepresentable {
  let trait: CombatTrait
  let coeff: Double

  static func fromValue(_ value: Value) -> ScaledTrait? {
    guard case let .list(spec) = value,
          spec.count == 2,
          let trait = CombatTrait.fromValue(spec[0]),
          let coeff = Double.fromValue(spec[1]) else {
      return nil
    }
    return ScaledTrait(trait: trait, coeff: coeff)
  }

  func toValue() -> Value {
    .list([trait.toValue(), coeff.toValue()])
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

// MARK: - core calculations

// Returns the effective armor level for a defender.
func armorLevel(_ avatar: Avatar) -> Double {
  avatar.equipped.reduce(0.0) { (partial, entry) in
    let (slot, item) = entry
    return partial + Double(item.effectiveLevel) * slot.armorMultiplier * item.armorMultiplier
  }
}

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
  let c = effectiveAttack * weapon.quality.coeff * (weapon.attack.speed / 3.0)
  let v = c  // FIXME: * weapon.variance
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
