//
//  ScriptLibrary.swift
//  Wyrm
//

struct NativeFunction: Callable {
  let fn: ([Value]) throws -> Value

  func call(_ args: [Value], context: [Scope]) throws -> CallableResult {
    return .value(try fn(args))
  }
}

struct ScriptLibrary {

  // All built-in functions available to scripts, in alphabetical order.
  static let functions = [
    ("addExit", wrap(addExit)),
    ("advanceQuest", wrap(advanceQuest)),
    ("announce", wrap(announce)),
    ("changeGender", wrap(changeGender)),
    ("changeName", wrap(changeName)),
    ("changeRace", wrap(changeRace)),
    ("completeQuest", wrap(completeQuest)),
    ("findExit", wrap(findExit)),
    ("giveItem", wrap(giveItem)),
    ("isa", wrap(isa)),
    ("len", wrap(len)),
    ("logDebug", logDebug),
    ("offerQuest", wrap(offerQuest)),
    ("oppositeDirection", wrap(oppositeDirection)),
    ("print", printValues),
    ("questPhase", wrap(questPhase)),
    ("random", wrap(random)),
    ("randomElement", wrap(randomElement)),
    ("receiveItems", wrap(receiveItems)),
    ("removeExit", wrap(removeExit)),
    ("show", wrap(show)),
    ("showNear", wrap(showNear)),
    ("showTutorial", wrap(showTutorial)),
    ("sleep", wrap(sleep)),
    ("spawn", wrap(spawn)),
    ("tell", wrap(tell)),
    ("travel", wrap(travel)),
    ("trunc", wrap(trunc)),
    ("updateMap", wrap(updateMap)),
  ]

  // Basic utility functions.

  static func isa(entity: Entity, proto: Entity) -> Bool {
    if let ref = proto.ref {
      return entity.isa(ref)
    } else {
      return entity == proto
    }
  }

  static func len(list: [Value]) -> Int {
    return list.count
  }

  static func printValues(_ args: [Value]) throws -> Value {
    print(args.map({ String(describing: $0) }).joined(separator: " "))
    return .nil
  }

  static func logDebug(_ args: [Value]) throws -> Value {
    logger.debug(args.map({ String(describing: $0) }).joined(separator: " "))
    return .nil
  }

  static func sleep(delay: Double) -> Value {
    .future { fn in World.schedule(delay: delay) { fn() } }
  }

  static func spawn(proto: Thing, location: Location, delay: Double) {
    World.schedule(delay: delay) {
      // FIXME: trigger an event
      location.insert(proto.clone())
    }
  }

  // Math functions.

  static func trunc(number: Double) -> Double {
    number.rounded(.towardZero)
  }

  // Random numbers and related functions.

  static func random(minValue: Double, maxValue: Double) -> Double {
    Double.random(in: minValue...maxValue)
  }

  static func randomElement(list: [Value]) -> Value {
    return list.randomElement() ?? .nil
  }

  // Functions that show output to players.

  static func announce(location: Location, radius: Int, message: String) {
    let map = Map(at: location, radius: radius)
    for cell in map.cells {
      cell.location.updateAll { $0.showNotice(message) }
    }
  }

  static func show(avatar: Avatar, message: String) {
    avatar.show(message)
  }

  static func showTutorial(avatar: Avatar, key: String, message: String) {
    avatar.showTutorial(key, message)
  }

  static func showNear(actor: Thing, message: String) {
    actor.location.updateAll { $0.show(message) }
  }

  static func tell(actor: Thing, avatar: Avatar, message: String) {
    avatar.showSay(actor, "says", message, false)
  }

  static func updateMap(location: Location) {
    let map = Map(at: location)
    for cell in map.cells {
      cell.location.updateAll { $0.showMap() }
    }
  }

  // Functions that change attributes of an avatar.

  static func changeGender(avatar: Avatar, gender: Gender) {
    avatar.gender = gender
    avatar.showNotice("You are now \(gender)!")
  }

  static func changeName(avatar: Avatar, name: String) -> Bool {
    // FIXME: more checks, capitalize
    if name.count >= 3 && name.count <= 15 {
      avatar.name = name
      avatar.showNotice("Your name is now \"\(name)\"!")
      return true
    } else {
      return false
    }
  }

  static func changeRace(avatar: Avatar, race: Race) {
    avatar.race = race
    avatar.showNotice("You are now \(race.describeBriefly([.indefinite]))!")
  }

  // Travel-related functions.

  static func addExit(portal: Portal, location: Location) -> Bool {
    return location.addExit(portal)
  }

  static func removeExit(direction: Direction, location: Location) -> Entity? {
    return location.removeExit(direction)
  }

  static func findExit(location: Location, direction: Direction) -> Portal? {
    return location.findExit(direction)
  }

  static func oppositeDirection(direction: Direction) -> Direction {
    return direction.opposite
  }

  static func travel(actor: Thing, exit: Portal) -> Bool {
    return actor.travel(via: exit)
  }

  // Quest-related functions.

  static func offerQuest(npc: Thing, quest: Quest, avatar: Avatar) -> Bool {
    return triggerEvent("offerQuest", in: avatar.location, participants: [npc, avatar],
                        args: [npc, quest, avatar]) {
      avatar.receiveOffer(QuestOffer(questgiver: npc, quest: quest))
      avatar.showNotice("""
                \(npc.describeBriefly([.capitalized, .definite])) has offered you the quest
                "\(quest.name)". Type `accept` to accept it.
                """)
    }
  }

  static func advanceQuest(avatar: Avatar, quest: Quest, progress: Value?) -> Bool {
    avatar.advanceQuest(quest, by: progress)
  }

  static func completeQuest(avatar: Avatar, quest: Quest) {
    avatar.completeQuest(quest)
  }

  static func questPhase(avatar: Avatar, quest: Quest) -> Value {
    if let state = avatar.activeQuests[quest.ref] {
      return .symbol(state.phase)
    } else if avatar.completedQuests[quest.ref] != nil {
      return .symbol("complete")
    } else {
      return .nil
    }
  }

  // Inventory-related functions.

  static func giveItem(avatar: Avatar, proto: Item, target: Thing) {
    avatar.giveItems(to: target) { $0.prototype == proto }
  }

  static func receiveItems(avatar: Avatar, items: [ItemStack], source: Thing) {
    avatar.receiveItems(items, from: source)
  }
}

// MARK: - helper functions

enum ScriptError: Error {
  case invalidArgument
  case tooManyArguments
}

extension ScriptLibrary {

  // Helper functions to unpack an array of argument values into a tuple of
  // specific types. Missing arguments are given a value of .nil in order to
  // accomodate optional arguments.

  static func unpack<T1: ValueRepresentable>
  (_ args: [Value], _ t1: T1.Type) throws -> T1 {
    guard args.count <= 1 else {
      throw ScriptError.tooManyArguments
    }
    var args = args.makeIterator()
    guard let v1 = T1.fromValue(args.next() ?? .nil) else {
      throw ScriptError.invalidArgument
    }
    return v1
  }

  static func unpack<T1: ValueRepresentable, T2: ValueRepresentable>
  (_ args: [Value], _ t1: T1.Type, _ t2: T2.Type) throws -> (T1, T2) {
    guard args.count <= 2 else {
      throw ScriptError.tooManyArguments
    }
    var args = args.makeIterator()
    guard let v1 = T1.fromValue(args.next() ?? .nil),
          let v2 = T2.fromValue(args.next() ?? .nil) else {
      throw ScriptError.invalidArgument
    }
    return (v1, v2)
  }

  static func unpack<T1: ValueRepresentable, T2: ValueRepresentable, T3: ValueRepresentable>
  (_ args: [Value], _ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type) throws -> (T1, T2, T3) {
    guard args.count <= 3 else {
      throw ScriptError.tooManyArguments
    }
    var args = args.makeIterator()
    guard let v1 = T1.fromValue(args.next() ?? .nil),
          let v2 = T2.fromValue(args.next() ?? .nil),
          let v3 = T3.fromValue(args.next() ?? .nil) else {
      throw ScriptError.invalidArgument
    }
    return (v1, v2, v3)
  }

  // Helper functions that wrap native functions to provide argument unpacking
  // and return value conversion.

  typealias Wrapper = ([Value]) throws -> Value

  static func wrap<T1: ValueRepresentable>
  (_ wrapped: @escaping (T1) -> Void) -> Wrapper {
    {
      let v1 = try unpack($0, T1.self)
      wrapped(v1)
      return .nil
    }
  }

  static func wrap<T1: ValueRepresentable, R: ValueRepresentable>
  (_ wrapped: @escaping (T1) -> R) -> Wrapper {
    {
      let v1 = try unpack($0, T1.self)
      return wrapped(v1).toValue()
    }
  }

  static func wrap<T1: ValueRepresentable, T2: ValueRepresentable>
  (_ wrapped: @escaping (T1, T2) -> Void) -> Wrapper {
    {
      let (v1, v2) = try unpack($0, T1.self, T2.self)
      wrapped(v1, v2)
      return .nil
    }
  }

  static func wrap<T1: ValueRepresentable, T2: ValueRepresentable, R: ValueRepresentable>
  (_ wrapped: @escaping (T1, T2) -> R) -> Wrapper {
    {
      let (v1, v2) = try unpack($0, T1.self, T2.self)
      return wrapped(v1, v2).toValue()
    }
  }

  static func wrap<T1: ValueRepresentable, T2: ValueRepresentable, T3: ValueRepresentable>
  (_ wrapped: @escaping (T1, T2, T3) -> Void) -> Wrapper {
    {
      let (v1, v2, v3) = try unpack($0, T1.self, T2.self, T3.self)
      wrapped(v1, v2, v3)
      return .nil
    }
  }

  static func wrap<T1: ValueRepresentable, T2: ValueRepresentable, T3: ValueRepresentable, R: ValueRepresentable>
  (_ wrapped: @escaping (T1, T2, T3) -> R) -> Wrapper {
    {
      let (v1, v2, v3) = try unpack($0, T1.self, T2.self, T3.self)
      return wrapped(v1, v2, v3).toValue()
    }
  }
}
