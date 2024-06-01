//
//  Inventory.swift
//  Wyrm
//

// The commands in this file implement the various ways a player can interact
// with their inventory:
//
// - take: location or container -> inventory
// - put: inventory -> container at location
// - receive: npc -> inventory
// - give: inventory -> npc
// - equip: inventory -> equipped
// - unequip: equipped -> inventory
// - discard: inventory -> nowhere

// MARK: - Avatar methods

extension Avatar {
  func discard(_ item: Item, count: Int? = nil) {
    var removed: ItemStack?
    if let count = count {
      if let remaining = inventory.remove(item, count: count) {
        if remaining > 0 {
          // FIXME: updateInventory(...)
        } else {
          // FIXME: removeFromInventory(...)
        }
        removed = ItemStack(item: item, count: count)
      }
    } else {
      if let count = inventory.removeAll(item) {
        // FIXME: removeFromInventory(...)
        removed = ItemStack(item: item, count: count)
      }
    }
    if removed != nil {
      show("You discard \(removed!.describeBriefly([.indefinite])).")
    } else {
      show("You don't have that many \(item.describeBriefly([.plural])).")
    }
  }

  func discardItems(where pred: (Item) -> Bool) {
    let stacks = inventory.select(where: pred)
    if !stacks.isEmpty {
      // FIXME: removeFromInventory(stacks)
      show("You discard \(stacks.describe()).")
      inventory.remove(stacks)
    }
  }

  func giveItems(to target: PhysicalEntity, where pred: (Item) -> Bool) {
    let stacks = inventory.select(where: pred)
    if !stacks.isEmpty {
      // FIXME: removeFromInventory(stacks)
      show("You give \(stacks.describe()) to \(target.describeBriefly([.definite])).")
      inventory.remove(stacks)
      for stack in stacks {
        triggerEvent("giveItem", in: location, participants: [self, stack.item, target],
                     args: [self, stack, target]) {}
      }
    }
  }

  func receiveItems(_ stacks: [ItemStack], from source: PhysicalEntity) {
    for stack in stacks {
      // FIXME: check if cannot insert
      let _ = inventory.insert(stack.item, count: stack.count)
    }
    // FIXME: checkEncumbrance()
    // FIXME: updateInventory(stacks)
    show("\(source.describeBriefly([.capitalized, .definite])) gives you \(stacks.describe()).")
  }

  func takeItem(_ stack: ItemStack, from source: Entity? = nil) {
#if false
    // FIXME: The source is either the location's item pile or some container at the location.

    // TODO: handle case with source other than location.
    // TODO: handle quantity.
    if inventory.canInsert(stack.item, count: stack.count) {
      triggerEvent("take", in: location, participants: [self, stack.item, location],
                   args: [self, stack, location]) {
        location.remove(item)
        removeNeighbor(item)
        updateInventory([inventory.insert(item)!])
        show("You take \(item.describeBriefly([.definite])).")
      }
    } else {
      show("You cannot carry any more \(item.describeBriefly([.plural])).")
    }
#endif
  }

  func putItem(_ item: ItemStack, into container: Container) {
#if false
    // FIXME: container is either the location's item pile or some container.

    if container.contents.canInsert(item) {
      triggerEvent("put", in: location, participants: [self, item.item, container],
                   args: [self, item, container]) {
        let (removed, remaining) = inventory.remove(item.item, count: item.count)
        if let removed = removed {
          removeFromInventory([removed])
          container.contents.insert(removed)
          show("You put \(removed.describeBriefly([.indefinite])) into \(container.describeBriefly([.definite])).")
        }
      }
    } else {
      show("\(container.describeBriefly([.capitalized, .definite])) cannot hold any more \(item.describeBriefly([.plural])).")
    }
#endif
  }

  func equip(_ item: Equipment) {
    // TODO: deal with explicit slot
    var slot: EquipmentSlot!
    switch item.slot {
    case .bothHands:
      unequip(in: .mainHand)
      unequip(in: .offHand)
      slot = .mainHand
    case .eitherHand:
      if equipped[.mainHand] == nil {
        slot = .mainHand
      } else if equipped[.offHand] == nil {
        slot = .offHand
      } else {
        unequip(in: .offHand)
        slot = .offHand
      }
    case .eitherFinger:
      // FIXME:
      return
    default:
      unequip(in: item.slot!)
      slot = item.slot!
    }
    let _ = inventory.remove(item)
    equipped[slot] = item
    removeFromInventory([ItemStack(item: item, count: 1)])
    updateEquipment([slot])
    show("You equip \(item.describeBriefly([.definite])).")
  }

  func unequip(in slot: EquipmentSlot) {
    if let item = equipped.removeValue(forKey: slot) {
      show("You return \(item.describeBriefly([.definite])) to your inventory.")
      let _ = inventory.insert(item)
      updateInventory([ItemStack(item: item, count: 1)])
      updateEquipment([slot])
    }
  }

  func hasEquipped(_ ref: Ref) -> Bool {
    return equipped.values.contains { $0.isa(ref) }
  }
}

// MARK: - inventory command

let inventoryHelp = """
Use the `inventory` command to list the items you have equipped or are carrying.
Optionally, add the name of an item to see a more detailed description of that
item.
"""

let wieldSlots: [EquipmentSlot] = [.mainHand, .offHand]

let wearSlots: [EquipmentSlot] = [.head, .torso, .back, .hands, .waist, .legs, .feet,
                                  .ears, .neck, .leftWrist, .rightWrist, .leftFinger, .rightFinger,
                                  .backpack, .beltPouch]

let toolSlots: [EquipmentSlot] = [.tool]

let inventoryCommand = Command("inventory item", help: inventoryHelp) {
  actor, verb, clauses in
  if case let .tokens(item) = clauses[0] {
    var matched = false
    if let matches = match(item, againstValues: actor.equipped) {
      for slot in matches {
        let item = actor.equipped[slot]!
        actor.show("\(item.describeBriefly([.capitalized, .indefinite])) (equipped): \(item.describeFully())")
      }
      matched = true
    }
    if let matches = match(item, against: actor.inventory.items.keys) {
      for item in matches {
        actor.show("\(item.describeBriefly([.capitalized, .indefinite])) (in inventory): \(item.describeFully())")
      }
      matched = true
    }
    if !matched {
      actor.show("You don't have anything like that equipped or in your inventory.")
    }
  } else {
    let wielded = wieldSlots.compactMap { actor.equipped[$0] }
    if wielded.isEmpty {
      actor.show("You are not wielding any weapons.")
    } else {
      actor.show("You are wielding \(wielded.describe()).")
    }

    let tools = toolSlots.compactMap { actor.equipped[$0] }
    if tools.isEmpty {
      actor.show("You have no tool at the ready.")
    } else {
      actor.show("You have \(tools.describe()) at the ready.")
    }

    let worn = wearSlots.compactMap { actor.equipped[$0] }
    if worn.isEmpty {
      actor.show("You are not wearing anything. A bold choice!")
    } else {
      actor.show("You are wearing \(worn.describe()).")
    }

    if actor.inventory.isEmpty {
      actor.show("You are not carrying anything.")
    } else {
      actor.show("You are carrying \(actor.inventory.describe()).")
    }
  }
}

// MARK: - take command

let takeHelp = """
Use the `take` command to take an item from your environment and place it into
your inventory. Some examples:

- `take pebble` to take a pebble the floor.

- `take letter from desk` to take a letter that is on a desk.
"""

let takeCommand = Command("take item from:container", help: takeHelp) {
  actor, verb, clauses in
  if case let .tokens(item) = clauses[0] {
    guard let matches = match(item, against: actor.location.contents, where: {
      $0.isVisible(to: actor)
    }) else {
      actor.show("You don't see anything like that here.")
      return
    }

    for entity in matches {
      if let item = entity as? Item {
        actor.takeItem(ItemStack(item: item, count: 1))  // FIXME: quantity
      } else {
        actor.show("You cannot take \(entity.describeBriefly([.definite])).")
      }
    }
  } else {
    actor.show("What do you want to take?")
  }
}

// MARK: - equip command

let equipCommand = Command("equip item in|on:slot") {
  actor, verb, clauses in
  if case let .tokens(item) = clauses[0] {
    let equipment = actor.inventory.items.keys.compactMap { $0 as? Equipment }
    guard let matches = match(item, against: equipment) else {
      actor.show("You aren't carrying any equipment like that.")
      return
    }
    guard matches.count == 1 else {
      actor.show("Do you want to equip \(matches.describe(using: "or"))?")
      return
    }
    actor.equip(matches.first!)
  } else {
    actor.show("What do you want to equip?")
  }
}

// MARK: - unequip command

let unequipCommand = Command("unequip item from:slot") {
  actor, verb, clauses in
  if case let .tokens(item) = clauses[0] {
    guard let matches = match(item, againstValues: actor.equipped) else {
      actor.show("You don't have anything like that equipped.")
      return
    }
    guard matches.count == 1 else {
      let matchedItems = matches.map { actor.equipped[$0]! }
      actor.show("Do you want to equip \(matchedItems.describe(using: "or"))?")
      return
    }
    actor.unequip(in: matches.first!)
  } else {
    actor.show("What do you want to unequip?")
  }
}
