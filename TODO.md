# accessing values

- there are native properties and script members

- native properties are stored directly in swift class properties. They are ValueRepresentable.

- script members are Values, stored in the members dict defined by Entity and
  accessed via the Scope protocol

- native code needs to conveniently access script members, and scripts need to access
  native properties

- native code could access script members with e.g. Type.fromValue(entity.get("name")) ?? default
  all over the place but that is hardly convenient or readable.
  
- The @scriptValue macro attached to a stored property can hide the above, and also
  provide for a default value.
  
- Accessors provide a way for scripts to access native members.

- Need to clean up method naming:

  + getMember/setMember for Values stored in members dict. These are called directly from
    the @scriptValue macro.
  
  + getMember on Entity implements the policy of looking for the value up the prototype chain.
  
  + setMember always sets in the members dict of the Entity, ignoring prototypes.

  + getProperty/setProperty for accessing possibly native properties as Values from scripts
  
  + getProperty/setProperty implement checking superclasses for the desired property,
    and Entity (the root class) falls back to getMember/setMember.

# TODO...

- Add support for uncountable nouns via a special article \_. Proper nouns are already
  treated as uncountable.
  
- Collect client updates and send them at the end of a "frame". Maybe add an Update
  object to Avatar that collects them.

- Use a Container representing a "pile of items" in a Location instead of
  dumping items all over the place. This keeps things cleaner and also helps
  because an ItemStack is not an Entity and so can't be inside a location
  anyhow.

- Location.contents is a [Entity]; Container is an Entity; Container.contents is
  an ItemCollection.

- add `def command` for commands that have no interaction with the engine, e.g.
  meditate. It basically just triggers an event with the same name. The command
  itself is a responder and gets added to the observers. It could
  look like

    def command meditate {
      help = "..."
      allow meditate(actor) { ... }
      after meditate(actor) { ...}
    }

  Maybe add support for a simple grammar = "..." if needed.

  If there's a duration member use a generalized EventActivity, and allow
  startMessage, interruptMessage, finishMessage members.

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
