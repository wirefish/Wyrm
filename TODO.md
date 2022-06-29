- make return value optional by checking for an expression starting at the next token.

- improve error handling in parsing, eval, exec. not so many Error enum types.

- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- match event handler arguments against constraints.

- automatically pair up exits to share a portal. create missing opposite exits unless oneway?

- fix plural verb forms.

- fix exit dest in exec().

- fix crash in release?

- database

- basic server requests for auth, etc.

- session management with websockets

- figure out quest states and how npcs react based on them.

## Entity Changes

Get rid of Facet. Have a small hierarchy of Entity subclasses that implement
combinations of the following protocols:

- Viewable controls how the entity is seen by other entities. Properties: brief, pose, icon, description. Default impls of fullDescription(to: viewer), isVisible(to:), briefDescription(to:), etc.

- Matchable controls how the entity matches input text. Brief, alts. Impls of match(input:) that returns an enum .none, .partial, .exact for example.

- Container determines if the entity can contain other entities. capacity, size, contents.

- Carryable determines if the entity can be picked up and placed in inventory. size.

- Equippable. slot, attackCoeff, defenceCoeff, trait, traitCoeff, (number of added )inventorySlots, enhancements (e.g. runes gems etc)

- Wieldable: Equippable. damageType. Necessary?

BTW trait is an enum of like .power (adds attack), .protection (adds defence) .precision, .ferocity, and various affinities that increase attack and defense against attacks of a certain damage type, e.g. a specific element or physical type.

- Usable: how can the item be used, verbs/events that apply. charges, what happens when they go to zero, cooldown between uses.

- Traversable: can pass through this entity from one location to another. size, closeable, lockable, isOpen, isLocked, etc.

- Attackable. Combat stats. level.

Then the concrete class hierarchy is:

- Entity: ValueDictionary, has id, prototype, extra values, event handlers.

- Portal: Entity, Viewable, Matchable, Traversable

- Location: Entity, Container. Also has some of its own things like exits and how it is viewed.

- Item: Entity, Viewable, Matchable, Carryable, Usable. has level.

- Equipment: Item, Equippable

- Fixture: Entity, Viewable, Matchable, Container. Things like desks or obelisks that may or may not actually be able to contain things. (can have zero capacity)

- Creature: Entity, Viewable, Matchable, Attackable

- Note NPC is just a library prototype, a creature with .good attitude and some default handlers. Technically attackable except due to alignment, not by players.

- Avatar: Entity, Viewable, Matchable, Attackable. Not a subclass of Creature since it will implement the protocols very differently.

