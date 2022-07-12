- improve error handling in parsing, eval, exec. not so many Error enum types.

- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- fix crash in release?

- change containers to only allow one stack of something stackable. the stack limit for typical things can be large, and this allows for things like quest items where you can only carry so many at once.

- add generic verbs that are implied commands. parses rest of input and matches against contents of location. optional ignored prep. if matched entity defines the verb, triggers event, or if location defines verb, triggers event. things like meditate or talk that have no inherent mechanical effect (but unlike say equip) can use this and not require explicit commands.

- show tutorials

- offers and accept command. rescind offer when leaving location.

- when evaluating member initializers, disallow many expressions (calls, subscripts) that don't make sense in that context. restrict dot expressions and identifiers to be ValueRefs. make ref value representable. Defer lookup until required, e.g. clone operator, lhs of portal operator, or if setting into an entity/quest/race. This allows members to be (arrays of) ValueRef that aren't necessarily resolvable yet. In the context of a function body nothing needs to change since all defs will have been performed.
