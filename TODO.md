- make return value optional by checking for an expression starting at the next token.

- improve error handling in parsing, eval, exec. not so many Error enum types.

- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- automatically "twin" portals for corresponding exits. create missing opposite exits unless oneway?

- fix crash in release?

- database

- basic server requests for auth, etc.

- session management with websockets

- change containers to only allow one stack of something stackable. the stack limit for typical things can be large, and this allows for things like quest items where you can only carry so many at once.

- make quest state codable. maybe it shouldn't be a fully-general value?
