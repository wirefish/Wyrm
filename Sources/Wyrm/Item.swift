//
//  Item.swift
//  Wyrm
//

enum CodingError: Error {
  case badPrototype
}

// MARK: Item

// An Item represents an immutable, non-customizable object that can be picked up, carried,
// dropped, etc. Because it cannot be changed, there is no need to create a dynamic instance
// of an Item. In other words, all instances of the item in the world are just the same
// Item instance, which always has a non-nil ref. The intent is to minimize copying and
// memory use. Note that subclasses of Item (e.g. Equipment) may behave differently if they
// represent mutable, customizable items.
class Item: Thing, Codable {
  // If zero, this item cannot stack with other items inside an ItemCollection, and
  // the ItemCollection can contain more than one stack with the same prototype
  // (unless `unique` is true). If positive, the item can stack with other items with
  // the same prototype and an ItemCollection can contain at most one such stack.
  var stackLimit = 0

  var stackable: Bool { stackLimit >= 1 }

  // Limits an ItemCollection to contain at most one of this (unstackable) item.
  var unique = false

  // If present, the item level determines the overall power of the item and/or the level
  // required to use it.
  var level: Int?

  // Verbs that identify commands that can be used with this item as the "direct object".
  var verbs: [String]?

  // An item may be associated with a quest, in which case it is only available when
  // that quest is active and is discarded once the quest ends.
  var quest: Quest?

  // The price for which vendors sell this item.
  var price: ItemStack?

  override func copyProperties(from other: Entity) {
    let other = other as! Item
    stackLimit = other.stackLimit
    unique = other.unique
    level = other.level
    verbs = other.verbs
    quest = other.quest
    price = other.price
    super.copyProperties(from: other)
  }

  // Scope.

  private static let accessors = [
    "stackLimit": Accessor(\Item.stackLimit),
    "unique": Accessor(\Item.unique),
    "level": Accessor(\Item.level),
    "verbs": Accessor(\Item.verbs),
    "quest": Accessor(\Item.quest),
    "price": Accessor(\Item.price),
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }

  // Conform to Codable. Only the ref is encoded/decoded.

  enum CodingKeys: CodingKey { case prototype }

  required convenience init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)

    let protoRef = try c.decode(Ref.self, forKey: .prototype)
    guard let proto = World.instance.lookup(protoRef)?.asEntity(Item.self) else {
      throw CodingError.badPrototype
    }
    self.init(prototype: proto)
    copyProperties(from: proto)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(prototype!.ref!, forKey: .prototype)
  }

  // Viewable.

  override func isVisible(to observer: Avatar) -> Bool {
    if let quest = quest, observer.activeQuests[quest.ref] == nil {
      return false
    }
    return super.isVisible(to: observer)
  }

  override func describeBriefly(_ format: Format) -> String {
    return (brief ?? Self.defaultBrief).format(format)
  }

  func descriptionNotes() -> [String] {
    var notes = [String]()
    if self.quest != nil, case let .quest(quest) = world.lookup(self.quest!.ref) {
      notes.append("Quest: \(quest.name).")
    }
    if let level = level, level > 0 {
      notes.append("Level: \(level).")
    }
    return notes
  }

  override func describeFully() -> String {
    let base = super.describeFully()
    let notes = descriptionNotes()
    if notes.isEmpty {
      return base
    } else {
      return "\(base) (\(notes.joined(separator: " ")))"
    }
  }
}

// MARK: ItemStack

// An item stack represents a quantity of a specific item. If `item.stackable` is true,
// then `item.ref` must not be nil and `count` can be any positive integer up to
// `item.stackLimit`. If `item.stackable` is false, then `item.ref` must be nil and
// `count` must be 1.
struct ItemStack {
  let item: Item
  let count: Int

  #if DEBUG
  init(item: Item, count: Int) {
    if item.stackable {
      assert(item.ref != nil)
      assert(count > 0 && count <= item.stackLimit)
    } else {
      assert(item.ref == nil)
      assert(count == 1)
    }
    self.item = item
    self.count = count
  }
  #endif
}

extension ItemStack: ValueRepresentable {
  static func fromValue(_ value: Value) -> ItemStack? {
    switch value {
    case let .stack(stack): return stack
    case let .entity(e):
      if let item = e as? Item {
        return ItemStack(item: item, count: 1)
      } else {
        return nil
      }
    default: return nil
    }
  }

  func toValue() -> Value { .stack(self) }
}

extension ItemStack: Viewable {
  func describeBriefly(_ format: Format) -> String {
    return (item.brief ?? Item.defaultBrief).format(format, count: count)
  }
}

extension ItemStack: Matchable {
  func match(_ tokens: ArraySlice<String>) -> MatchQuality {
    return item.match(tokens)
  }
}

// MARK: ItemCollection

// An ItemCollection represents a set of stacks of identical items. When inserting
// and removing an item, its behavior depends on the `stackable`, `stackLimit`, and
// `unique` properties of the item in question.
//
// If `stackable` is true, then `stackLimit` identical items may be stacked together,
// and an ItemCollection can contain at most one stack for that item. This models the
// case where the item cannot be customized or changed, e.g. a gathered material such
// as a "lump of coal" or a consumable such as a "minor health potion". In this case
// the item will have a non-nil ref; in other words it is not dynamically created. The
// limitation of a single stack models cases where you can only carry so many of that
// item, e.g. a quest item. Most stackable items would have a large stackLimit value.
//
// If `stackable` is false, items cannot be stacked together. This models items that
// may be customized or change, such as equipment. In this case the item itself will
// have a nil ref and will have been cloned at runtime.
//
// Normally if `stackable` is false then the ItemCollection can contain any number of
// "stacks of one" for such an item (up to its capacity limit, if any). If `unique` is
// true, however, then only one such stack can exist. This can model special items
// like artifacts.
struct ItemCollection: Codable {
  var capacity: Int?
  var items = [Item:Int]()

  var isEmpty: Bool { items.isEmpty }
  var count: Int { items.count }

  private func containsItemWithPrototype(_ prototype: Entity) -> Bool {
    return items.keys.contains { $0.prototype === prototype }
  }

  func canInsert(_ item: Item, count: Int = 1) -> Bool {
    if item.stackable {
      assert(item.ref != nil)
      if let currentCount = items[item] {
        return currentCount + count < item.stackLimit
      } else {
        return capacity == nil || items.count < capacity!
      }
    } else {
      assert(count == 1)
      assert(item.ref == nil && item.prototype != nil)
      assert(items.index(forKey: item) == nil)
      return ((capacity == nil || items.count < capacity!) &&
              (!item.unique || !containsItemWithPrototype(item.prototype!)))
    }
  }

  // Adds `count` of `item` to the collection. Returns the resulting number of identical
  // items in the collection, or nil if the item cannot be inserted.
  mutating func insert(_ item: Item, count: Int = 1) -> Int? {
    if item.stackable {
      assert(item.ref != nil)
      if let currentCount = items[item] {
        // Add to existing stack unless it would overflow.
        if currentCount + count < item.stackLimit {
          items[item]! += count
          return currentCount + count
        } else {
          return nil
        }
      } else if capacity == nil || items.count < capacity! {
        // Add a new stack.
        items[item] = count
        return count
      } else {
        return nil
      }
    } else {
      // Add a new stack if capacity and uniqueness allow.
      assert(count == 1)
      assert(item.ref == nil && item.prototype != nil)
      assert(items.index(forKey: item) == nil)
      if ((capacity == nil || items.count < capacity!) &&
          (!item.unique || !containsItemWithPrototype(item.prototype!))) {
        items[item] = 1
        return 1
      } else {
        return nil
      }
    }
  }

  // Removes `count` of `item` from the collection. On success, returns the number of
  // identical items remaining in the collection, or nil if the collection does not
  // contain at least the specified number of `item`.
  mutating func remove(_ item: Item, count: Int = 1) -> Int? {
    if let index = items.index(forKey: item) {
      let currentCount = items[index].value
      if currentCount > count {
        // Shrink the existing stack.
        items[item]! -= count
        return currentCount - count
      } else if currentCount == count {
        // Remove the existing stack.
        items.remove(at: index)
        return count
      }
    }
    return nil
  }

  // Removes the entire stack associated with `item`. Returns the number of items removed
  // on success, or nil if `item` is not in the collection.
  @discardableResult
  mutating func removeAll(_ item: Item) -> Int? {
    if let index = items.index(forKey: item) {
      let count = items[index].value
      items.remove(at: index)
      return count
    } else {
      return nil
    }
  }

  func stacks() -> [ItemStack] {
    items.map { ItemStack(item: $0.key, count: $0.value) }
  }

  func select(where pred: (Item) -> Bool) -> [ItemStack] {
    items.compactMap { pred($0.key) ? ItemStack(item: $0.key, count: $0.value) : nil }
  }

  mutating func remove(_ stacks: [ItemStack]) {
    for stack in stacks {
      self.items.removeValue(forKey: stack.item)
    }
  }

  func describe() -> String { stacks().describe() }
}
