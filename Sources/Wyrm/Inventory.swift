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
        for item in items {
            inventory.insert(item, force: true)
        }
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
            triggerEvent("take", in: location, participants: [self, item],
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
