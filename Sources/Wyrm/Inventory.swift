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
