- make return value optional by checking for an expression starting at the next token.

- improve error handling in parsing, eval, exec. not so many Error enum types.

- quests. ValueDictionary already will deal with the properties, generalize event handling
  (Observer?) to share it with Entity.
  
- values that can be represented by arbitrary symbols, unlike enums. can make a Symbol class
  that just wraps a String for now.
  
- match event handler arguments against constraints. allow naked self constraint?

- automatically pair up exits to share a portal. create missing opposite exits unless oneway?

- fix plural verb forms.

- do we need clone initializers? they aren't needed for exits any more.

- fix exit dest in exec().
