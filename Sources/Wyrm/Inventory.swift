//
// Inventory.swift
// Wyrm
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

final class Inventory: Container {
    static let baseCapacity = 5

    required init(withPrototype proto: Entity? = nil) {
        super.init(withPrototype: proto)
        self.capacity = Self.baseCapacity
    }

    func updateCapacity(_ avatar: Avatar) {
        self.capacity = avatar.equipped.reduce(Self.baseCapacity) {
            return $0 + $1.1.capacity
        }
    }
}

// MARK: - Avatar methods

extension Avatar {
    func discard(_ item: Item, count: Int? = nil) {
        if let removed = inventory.remove(item, count: count) {
            if removed == item {
                // TODO: remove item from inventory pane
            } else {
                // TODO: update inventory pane with item's new count
            }
            show("You discard \(removed.describeBriefly([.indefinite])).")
        }
    }

    func discardItems(where pred: (Item) -> Bool) {
        let first = inventory.partition(by: pred)
        if first != inventory.endIndex {
            show("You discard \(inventory[first...].describe()).")
            inventory.remove(from: first)
        }
    }

    func giveItems(to target: PhysicalEntity, where pred: (Item) -> Bool) {
        let first = inventory.partition(by: pred)
        if first != inventory.endIndex {
            show("You give \(inventory[first...].describe()) to \(target.describeBriefly([.definite])).")
            for item in inventory.contents[first...] {
                triggerEvent("give_item", in: location, participants: [self, item, target],
                             args: [self, item, target]) {}
            }
            inventory.remove(from: first)
        }
    }

    func receiveItems(_ items: [Item], from source: PhysicalEntity) {
        let items = items.map { $0.clone() }
        items.forEach { inventory.insert($0, force: true) }
        // TODO: update inventory pane
        show("\(source.describeBriefly([.capitalized, .definite])) gives you \(items.describe()).")
    }

    func takeItem(_ item: Item, from source: Container? = nil) {
        // TODO: handle case with source other than location.
        // TODO: handle quantity.
        guard !inventory.isFull else {
            show("Your inventory is full.")
            return
        }
        if inventory.canInsert(item) {
            triggerEvent("take", in: location, participants: [self, item, location],
                         args: [self, item, location]) {
                location.remove(item)
                inventory.insert(item)
                removeNeighbor(item)
                show("You take \(item.describeBriefly([.definite])).")
            }
        } else {
            show("You cannot carry any more \(item.describeBriefly([.plural])).")
        }
    }

    func putItem(_ item: Item, into container: Container) {
        // TODO: handle quantity.
        guard !container.isFull else {
            show("\(container.describeBriefly([.capitalized, .definite])) is full.")
            return
        }
        if container.canInsert(item) {
            triggerEvent("put", in: location, participants: [self, item, container],
                         args: [self, item, container]) {
                inventory.remove(item)
                container.insert(item)
                show("You put \(item.describeBriefly([.indefinite])) into \(container.describeBriefly([.definite])).")
            }
        } else {
            show("\(container.describeBriefly([.capitalized, .definite])) cannot accept any more \(item.describeBriefly([.plural])).")
        }
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
        inventory.remove(item)
        equipped[slot] = item
        updateEquipment([slot])
        show("You equip \(item.describeBriefly([.definite])).")
    }

    func unequip(in slot: EquipmentSlot) {
        if let item = equipped.removeValue(forKey: slot) {
            show("You return \(item.describeBriefly([.definite])) to your inventory.")
            inventory.insert(item, force: true)
            // TODO: update equipment and inventory panes.
            updateEquipment([slot])
        }
    }
}

// MARK: - inventory command

let inventoryHelp = """
Use the `inventory` command to list or inspect items you are carrying.

- Type `inventory` to list the items you are carrying.

- Type `inventory look` followed by the name of an item in your inventory to
inspect that item.
"""

let inventoryCommand = Command("inventory 1:subcommand item", help: inventoryHelp) {
    actor, verb, clauses in
    if actor.inventory.isEmpty {
        actor.show("You are not carrying anything.")
    } else {
        actor.show("You are carrying \(actor.inventory.describe()).")
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
                actor.takeItem(item)
            } else {
                actor.show("You cannot take \(entity.describeBriefly([.definite])).")
            }
        }
    } else {
        actor.show("What do you want to take?")
    }
}

// MARK: - equip command

let wieldSlots: [EquipmentSlot] = [.mainHand, .offHand]

let wearSlots: [EquipmentSlot] = [.head, .torso, .back, .hands, .waist, .legs, .feet,
                                  .ears, .neck, .leftWrist, .rightWrist, .leftFinger, .rightFinger,
                                  .backpack, .beltPouch]

let toolSlots: [EquipmentSlot] = [.tool]

let equipCommand = Command("equip item in|on:slot") {
    actor, verb, clauses in
    if case let .tokens(item) = clauses[0] {
        guard let matches = match(item, against: actor.inventory.compactMap { $0 as? Equipment}) else {
            actor.show("You aren't carrying any equipment like that.")
            return
        }
        guard matches.count == 1 else {
            actor.show("Do you want to equip \(matches.describe(using: "or"))?")
            return
        }
        actor.equip(matches.first!)
    } else {
        let wielded = wieldSlots.compactMap { actor.equipped[$0] }
        if wielded.isEmpty {
            actor.show("You are not wielding any weapons.")
        } else {
            actor.show("You are wielding \(wielded.describe()).")
        }
        let worn = wearSlots.compactMap { actor.equipped[$0] }
        if worn.isEmpty {
            actor.show("You are not wearing anything. A bold choice!")
        } else {
            actor.show("You are wearing \(worn.describe()).")
        }
    }
}

// MARK: - unequip command

let unequipCommand = Command("unequip item from:slot") {
    actor, verb, clauses in
    if case let .tokens(item) = clauses[0] {
        guard let matches = match(item, against: actor.equipped) else {
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
