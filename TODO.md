- remove `of` operator and use more general !(...) instead

- expression if

- add `def command` for commands that have no interaction with the engine, e.g.
  meditate.

- add `def event` for similar reasons to above

# Older...

- improve error handling in parsing, eval, exec. not so many Error enum types.

- fix crash in release?

- add generic verbs that are implied commands. parses rest of input and matches
  against contents of location. optional ignored prep. if matched entity defines
  the verb, triggers event, or if location defines verb, triggers event. things
  like meditate or talk that have no inherent mechanical effect (but unlike say
  equip) can use this and not require explicit commands.

- nice to have: lighter weight message to update specific map locations.

- better way to get reasonable default size for various entity subclasses

- make spawn() generate an event, at least enterLocation

- events for take/put/etc?

- fix inventory pane updates when items are merged/split

- handle quantities in take/put/give/discard.

- allow explicit slot in (un)equip.

- icons.

- vendors: buy and sell. add prices to items.

- move tutorials seen and completed quests to separate tables in the database,
  since they just keep growing and resaving them every time will become slower
  and slower.

- use command

- give command

- gather command, gathering nodes

- location inherit domain from region?

- add hidden and implied flags to PhysicalEntity, replace isObvious with implied.

- add bound flag to Item.

- use an option set for all the flags? would need Accessor to work.

- drop loot. One idea: take the list of avatars on the enemy list, keeping those
  that are alive and at the same location. Generate the list of items. Then
  randomly sort the list of avatars and assign an item to each person in the
  randomized list, repeating until all items are assigned. Maybe have a way of
  saying "everyone gets this item" for special drops.
