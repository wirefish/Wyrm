//
// Inventory.swift
// Wyrm
//
// The commands in this file implement the various ways a player can interact
// with their inventory:
//
// - take: environment -> inventory
// - put: inventory -> environment
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

    func discardAll(withPrototype ref: ValueRef) {
        let first = inventory.contents.partition { $0.prototype?.ref == ref }
        for item in inventory.contents[first...] {
            // TODO: remove item from inventory pane
            show("You discard \(item.describeBriefly([.indefinite])).")
        }
        inventory.contents.remove(from: first)
    }

    func giveItems(to target: PhysicalEntity, where pred: (Item) -> Bool ) {
        let first = inventory.contents.partition(by: pred)
        if first != inventory.contents.endIndex {
            let desc = inventory.contents[first...].map { $0.describeBriefly([.indefinite]) }
            show("You give \(desc.conjunction(using: "and")) to \(target.describeBriefly([.definite])).")
            for item in inventory.contents[first...] {
                triggerEvent("give_item", in: location, participants: [self, item, target],
                             args: [self, item, target]) {}
            }
            inventory.contents.remove(from: first)
        }
    }

    func receiveItems(_ items: [Item], from source: PhysicalEntity) {
        let items = items.map { $0.clone() }
        for item in items {
            inventory.insert(item, force: true)
        }
        // TODO: update inventory pane
        let desc = items.map { $0.describeBriefly([.indefinite]) }
        show("\(source.describeBriefly([.capitalized, .definite])) gives you \(desc.conjunction(using: "and")).")
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

    let items = actor.inventory.contents.map { $0.describeBriefly([.indefinite]) }
    if items.isEmpty {
        actor.show("You are not carrying anything.")
    } else {
        actor.show("You are carrying \(items.conjunction(using: "and")).")
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
            if actor.inventory.isFull {
                actor.show("Your inventory is full.")
                break
            } else if let item = entity as? Item {
                if actor.inventory.canInsert(item) {
                    triggerEvent("take", in: actor.location, participants: [actor, item],
                                 args: [actor, item, actor.location]) {
                        actor.location.remove(item)
                        actor.inventory.insert(item)
                        actor.show("You take \(item.describeBriefly([.definite])).")
                    }
                } else {
                    actor.show("You cannot carry any more \(item.describeBriefly([.plural])).")
                }
            } else {
                actor.show("You cannot take \(entity.describeBriefly([.definite])).")
            }
        }

        for item in matches {
        }
    } else {
        actor.show("What do you want to take?")
    }
}
