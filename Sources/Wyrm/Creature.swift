//
//  Creature.swift
//  Wyrm
//

import Darwin

// MARK: - LootTable

struct LootEntry {
  let probability: Double
  let minCount: Int
  let maxCount: Int
  let prototype: Item
}

extension LootEntry: ValueRepresentable {
  static func fromValue(_ value: Value) -> LootEntry? {
    guard case let .list(list) = value,
          list.count == 4,
          let probability = Double.fromValue(list[0]),
          let minCount = Int.fromValue(list[1]),
          let maxCount = Int.fromValue(list[2]),
          let prototype = Item.fromValue(list[3]) else {
      return nil
    }
    return LootEntry(probability: probability, minCount: minCount, maxCount: maxCount,
                     prototype: prototype)
  }

  func toValue() -> Value {
    let values: [Value] = [.number(probability), .number(Double(minCount)),
                           .number(Double(maxCount)), .entity(prototype)]
    return .list(values)
  }
}

typealias LootTable = [LootEntry]

extension LootTable {
  func generateItems() -> [ItemStack] {
    compactMap { entry in
      if Double.random(in: 0..<1) < entry.probability {
        return ItemStack(item: entry.prototype.stackable ? entry.prototype : entry.prototype.clone(),
                         count: Int.random(in: entry.minCount...entry.maxCount))
      } else {
        return nil
      }
    }
  }
}

// MARK: - EnemyList

struct Enemy {
  var aggro: Double
  weak var target: Entity?
}

typealias EnemyList = [Enemy]

extension EnemyList {
  // Maintains the list in descending order by aggro amount.
  mutating func update(amount: Double, target: Entity) {
    if let index = firstIndex(where: { $0.target == target }) {
      self[index].aggro += amount
      bubbleUp(index)
    } else {
      append(Enemy(aggro: amount, target: target))
      bubbleUp(endIndex - 1)
    }
  }

  func firstTarget() -> Entity? {
    for entry in self {
      if let target = entry.target {
        return target
      }
    }
    return nil
  }

  mutating func removeTarget(target: Entity) {
    if let index = firstIndex(where: { $0.target == target }) {
      remove(at: index)
    }
  }

  mutating func decay(_ factor: Double) {
    removeAll { $0.target == nil }
    for index in indices {
      self[index].aggro *= factor
    }
  }

  private mutating func bubbleUp(_ index: Int) {
    var index = index
    while index > startIndex && self[index].aggro > self[index - 1].aggro {
      swapAt(index - 1, index)
      index -= 1
    }
  }
}

// MARK: - Creature

class Creature: Thing, Combatant, Questgiver {
  // Combatant
  var level = 1
  var health = 1
  var minHealth = 0
  var attitude = Attitude.neutral
  var weapons = [Weapon]()
  var loot: LootTable?
  var equipped: [EquipmentSlot:Equipment] { [:] }

  var enemies = [Enemy]()

  // Questgiver
  var offersQuests = [Quest]()

  var sells: [Item]?
  var teaches: [Skill]?

  // Traits specified in the script file.
  var inherentCombatTraits = [CombatTrait:Int]()

  // Cached traits combined from all sources.
  var combatTraits = [CombatTrait:Int]()

  func recomputeCombatTraits() {
    combatTraits = inherentCombatTraits
  }

  override func copyProperties(from other: Entity) {
    let other = other as! Creature
    level = other.level
    minHealth = other.minHealth
    attitude = other.attitude
    weapons = other.weapons
    loot = other.loot
    // don't copy enemies
    offersQuests = other.offersQuests
    sells = other.sells
    teaches = other.teaches
    super.copyProperties(from: other)

    health = maxHealth()
  }

  private static let accessors = [
    "level": Accessor(\Creature.level),
    "minHealth": Accessor(\Creature.minHealth),
    "traits": Accessor(writeOnly: \Creature.inherentCombatTraits),
    "weapons": Accessor(\Creature.weapons),
    "loot": Accessor(\Creature.loot),
    "offersQuests": Accessor(\Creature.offersQuests),
    "sells": Accessor(\Creature.sells),
    "teaches": Accessor(\Creature.teaches),
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }

  func defense(against damageType: DamageType) -> Int {
    0
  }

  func nextAttack(against target: Combatant) -> Attack? {
    nil
  }
}
