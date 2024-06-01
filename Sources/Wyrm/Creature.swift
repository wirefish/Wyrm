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

class Creature: PhysicalEntity, Combatant, Questgiver {
  // Attackable
  var level = 1
  var health = ClampedInt(1, maxValue: 1)
  var minHealth = 0
  var attack_coeff = 1.0
  var defense_coeff = 1.0
  var health_coeff = 1.0
  var weapons = [Weapon]()
  var loot: LootTable?

  var enemies = [Enemy]()

  // Questgiver
  var offersQuests = [Quest]()

  var sells: [Ref]?
  var teaches: [Ref]?

  override func copyProperties(from other: Entity) {
    let other = other as! Creature
    level = other.level
    attack_coeff = other.attack_coeff
    defense_coeff = other.defense_coeff
    health_coeff = other.health_coeff
    weapons = other.weapons
    loot = other.loot
    // don't copy enemies
    offersQuests = other.offersQuests
    sells = other.sells
    teaches = other.teaches
    super.copyProperties(from: other)

    health.maxValue = Int(health_coeff * Double(baseHealth(level: level)))
    health.value = health.maxValue
  }

  private static let accessors = [
    "level": Accessor(\Creature.level),
    "minHealth": Accessor(\Creature.minHealth),
    "attackCoeff": Accessor(\Creature.attack_coeff),
    "defenseCoeff": Accessor(\Creature.defense_coeff),
    "healthCoeff": Accessor(\Creature.health_coeff),
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
