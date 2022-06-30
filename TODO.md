- make return value optional by checking for an expression starting at the next token.

- improve error handling in parsing, eval, exec. not so many Error enum types.

- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- automatically pair up exits to share a portal. create missing opposite exits unless oneway?

- fix plural verb forms.

- fix crash in release?

- database

- basic server requests for auth, etc.

- session management with websockets

- figure out quest states and how npcs react based on them.

- combat traits. trait is an enum of like .power (adds attack), .protection (adds defence) .precision, .ferocity, and various affinities that increase attack and defense against attacks of a certain damage type, e.g. a specific element or physical type.
