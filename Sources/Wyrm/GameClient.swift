//
//  GameClient.swift
//  Wyrm
//

let notes = """

The client UI state comprises the the following components:

- AvatarState (top bar): icon, name, race, level, health/energy/mana, auras

- [NeighborState] (left side): each has id, icon, label, opt health bar,
  status (passive/friendly/neutral/unfriendly)

- Map (upper right): region name + [MapCell], each with id, x, y, exits, icon (e.g. boat),
  markers (e.g. vendor, quest, etc)

- main text and chat text: append only, [(fn, args)]

- hotbar: [(Icon, Name, Action)] all are strings, action is implied command/skill to use

The bottom right pane has several tabs:

- equipment: [Slot:EquippedItem] where item has icon, name

- inventory: [InventoryItem] where item has icon, name, quantity, group, and subgroup
  (for client-side sorting and/or partitioning)

- combat attributes: [String:Int]

- skills: unspent karma + [Skill]: name, rank, maxRank

- activity status: either a castbar (for non-modal activities) or specific state
  for each modal activity such as combat or crafting.

The update message can be reduced to an array of (fn, args) that are called in order.

"""

struct ClientCall: Encodable {
  let fn: String
  let args: [ClientValue]
}

enum ClientValue: Encodable {
  case boolean(Bool?)
  case integer(Int?)
  case double(Double?)
  case string(String?)
  case list([ClientValue])

  func encode(to encoder: Encoder) throws {
    switch self {
    case let .boolean(b):
      var c = encoder.singleValueContainer()
      try c.encode(b)
    case let .integer(i):
      var c = encoder.singleValueContainer()
      try c.encode(i)
    case let .double(d):
      var c = encoder.singleValueContainer()
      try c.encode(d)
    case let .string(s):
      var c = encoder.singleValueContainer()
      try c.encode(s)
    case let .list(list):
      var c = encoder.unkeyedContainer()
      for value in list {
        try c.encode(value)
      }
    }
  }
}

// MARK: Equipment and inventory

struct ItemProperties: Encodable {
  let brief: String
  let icon: String?

  init(_ item: Item) {
    brief = item.describeBriefly([])
    icon = item.icon
  }
}

extension Avatar {
  func updateEquipment<S: Sequence>(_ slots: S) where S.Element == EquipmentSlot {
    let update = [EquipmentSlot:ItemProperties?].init(uniqueKeysWithValues: slots.map {
      slot -> (EquipmentSlot, ItemProperties?) in
      if let item = equipped[slot] {
        return (slot, ItemProperties(item))
      } else {
        return (slot, nil)
      }
    })
    sendMessage("updateEquipment", [update])
  }

  func updateInventory(_ stacks: any Sequence<ItemStack>) {
    let update = [Int:ItemProperties].init(uniqueKeysWithValues: stacks.map {
      ($0.item.id, ItemProperties($0.item))
    })
    sendMessage("updateInventory", [update])
  }

  func removeFromInventory(_ stacks: any Sequence<ItemStack>) {
    let update = [Int:ItemProperties?].init(uniqueKeysWithValues: stacks.map {
      ($0.item.id, nil)
    })
    sendMessage("updateInventory", [update])
  }
}

// MARK: Avatar

struct AvatarProperties: Encodable {
  var name: String? = nil
  var icon: String? = nil
  var level: Int? = nil
  var xp: Int? = nil
  var maxXP: Int? = nil
}

extension Avatar {
  func updateSelf(_ properties: AvatarProperties) {
    sendMessage("updateAvatar", [properties])
  }
}
