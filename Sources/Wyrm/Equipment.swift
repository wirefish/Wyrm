//
//  Equipment.swift
//  Wyrm
//

enum EquipmentSlot: String, CodingKeyRepresentable, Hashable, Codable, ValueRepresentableEnum {
  // Weapons and tools.
  case mainHand, offHand, tool

  // Clothing.
  case head, torso, back, hands, waist, legs, feet

  // Accessories.
  case ears, neck, leftWrist, rightWrist, leftFinger, rightFinger, trinket

  // Storage.
  case backpack, beltPouch

  // Meta-slots.
  case bothHands, eitherHand, eitherWrist, eitherFinger

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })

  var coeff: Double {
    switch self {
    case .mainHand: return 1.0
    case .offHand: return 1.0
    case .tool: return 1.0

    case .head: return 0.6
    case .torso: return 1.0
    case .back: return 0.5
    case .hands: return 0.5
    case .waist: return 0.4
    case .legs: return 1.0
    case .feet: return 0.5

    case .ears: return 0.5
    case .neck: return 0.5
    case .leftWrist: return 0.25
    case .rightWrist: return 0.25
    case .leftFinger: return 0.25
    case .rightFinger: return 0.25
    case .trinket: return 0.5

    case .backpack: return 1.0
    case .beltPouch: return 0.5

    case .bothHands: return 2.0
    case .eitherHand: return 1.0
    case .eitherWrist: return 0.25
    case .eitherFinger: return 0.25
    }
  }

  // A multiplier that applies to the armor level provided by an item equipped
  // in a clothing slot (excluding back and waist). The values sum to one, with the
  // exception of .offHand -- this is meant to model the extra defense bonus of
  // using a shield.
  var armorMultiplier: Double {
    switch self {
    case .offHand: 0.3
    case .head:  0.2
    case .torso:  0.3
    case .hands:  0.1
    case .legs:  0.3
    case .feet:  0.1
    default: 0.0
    }
  }

  var defenseCoeff: Double {
    switch self {
    case .head, .torso, .back, .hands, .waist, .legs, .feet: return coeff
    default: return 0.0
    }
  }
}

enum EquipmentQuality: Encodable, Comparable, ValueRepresentableEnum {
  case poor, normal, fine, masterwork, legendary

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })

  var levelModifier: Int {
    switch self {
    case .poor: -1
    case .normal: 0
    case .fine: 1
    case .masterwork: 2
    case .legendary: 3
    }
  }

  var coeff: Double {
    switch self {
    case .poor: return 0.75
    case .normal: return 1.0
    case .fine: return 1.25
    case .masterwork: return 1.5
    case .legendary: return 1.75
    }
  }
}

// MARK: Equipment

class Equipment: Item {
  // Ensure equipment is never considered stackable.
  override var stackLimit: Int {
    get { 0 }
    set { }
  }
  override var stackable: Bool { false }

  // The slot in which this item can be equipped.
  var slot: EquipmentSlot?

  // The item quality modifies the effective level of the item without raising
  // the level requirement to use it.
  var quality: EquipmentQuality = .normal

  var effectiveLevel: Int { (level ?? 0) + quality.levelModifier }

  // Combat bonuses gained when the item is equipped.
  var traits = [CombatTrait:Int]()

  // Inventory capacity gained by equipping this item.
  var capacity = 0

  // Skill required in order to equip the item without penalty, if any.
  var proficiency: Skill?

  // A multiplier that modifies the armor bonus of this item when equipped.
  var armorMultiplier = 0.0

  override func copyProperties(from other: Entity) {
    let other = other as! Equipment
    slot = other.slot
    quality = other.quality
    traits = other.traits
    capacity = other.capacity
    proficiency = other.proficiency
    armorMultiplier = other.armorMultiplier
    super.copyProperties(from: other)
  }

  private static let accessors = [
    "slot": Accessor(\Equipment.slot),
    "quality": Accessor(\Equipment.quality),
    "traits": Accessor(writeOnly: \Equipment.traits),
    "capacity": Accessor(\Equipment.capacity),
    "proficiency": Accessor(\Equipment.proficiency),
    "armorMultiplier": Accessor(\Equipment.armorMultiplier),
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }

  var traitValue: Double {
    if let level = level {
      Double(level) * 10.0 * quality.coeff * slot!.coeff
    } else {
      0.0
    }
  }

  override func descriptionNotes() -> [String] {
    var notes = super.descriptionNotes()
    if quality != .normal {
      notes.append("Quality: \(String(describing: quality)).")
    }
    for (trait, level) in traits {
      notes.append(String(format: "Trait: %@ +%d.", trait.description, level))
    }
    return notes
  }

}

// MARK: Weapon

struct Attack_ {
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

class Weapon: Equipment {
  var attack = Attack_()

  override func copyProperties(from other: Entity) {
    let other = other as! Weapon
    attack = other.attack
    super.copyProperties(from: other)
  }

  private static let accessors = [
    "damageType": Accessor(\Weapon.attack.damageType),
    "damage": Accessor(\Weapon.attack.damage),
    "speed": Accessor(\Weapon.attack.speed),
    "attackVerb": Accessor(\Weapon.attack.verb),
    "criticalVerb": Accessor(\Weapon.attack.criticalVerb),
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }

  var attackValue: Double {
    if let level = level {
      Double(level + (slot == .bothHands ? 1 : 0)) * 20.0
    } else {
      0.0
    }
  }

  override func descriptionNotes() -> [String] {
    var notes = super.descriptionNotes()
    notes.append(String(format: "Attack: %1.1f.", attackValue))
    return notes
  }
}
