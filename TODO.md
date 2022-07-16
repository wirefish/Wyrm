- improve error handling in parsing, eval, exec. not so many Error enum types.

- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- fix crash in release?

- add generic verbs that are implied commands. parses rest of input and matches against contents of location. optional ignored prep. if matched entity defines the verb, triggers event, or if location defines verb, triggers event. things like meditate or talk that have no inherent mechanical effect (but unlike say equip) can use this and not require explicit commands.

- nice to have: lighter weight message to update specific map locations.

- better way to get reasonable default size for various entity subclasses

- respawn after delay, wrap in event

- events for take/put/etc?

- fix inventory pane updates when items are merged/split

- handle quantities in take/put/give/discard.

- allow explicit slot in (un)equip.

- icons.

- save avatar. manually for now.
