//
//  Avatar.swift
//  Wyrm
//

import Foundation  // for JSONEncoder

// MARK: - Race

final class Race: Scope, CustomDebugStringConvertible {
  let ref: Ref
  var brief: NounPhrase?
  var description: String?

  init(ref: Ref) {
    self.ref = ref
  }

  static let accessors = [
    "brief": Accessor(\Race.brief),
    "description": Accessor(\Race.description),
  ]

  func get(_ member: String) -> Value? {
    getMember(member, Self.accessors)
  }

  func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors)
  }

  func describeBriefly(_ format: Text.Format) -> String {
    // FIXME:
    return brief!.format(format)
  }

  var debugDescription: String { "<Race \(ref)>" }
}

// MARK: - Skill

final class Skill: Scope, Matchable, CustomDebugStringConvertible {
  let ref: Ref
  var name: String?
  var description: String?
  var maxRank = 200
  var karmaPrice: Int?
  var currencyPrice: Item?
  var requiredSkills: [Ref]?
  var exclusiveSkills: [Ref]?

  init(ref: Ref) {
    self.ref = ref
  }

  static let accessors = [
    "name": Accessor(\Skill.name),
    "description": Accessor(\Skill.description),
    "maxRank": Accessor(\Skill.maxRank),
    "karmaPrice": Accessor(\Skill.karmaPrice),
    "currencyPrice": Accessor(\Skill.currencyPrice),
    "requiredSkills": Accessor(\Skill.requiredSkills),
    "exclusiveSkills": Accessor(\Skill.exclusiveSkills),
  ]

  func get(_ member: String) -> Value? {
    getMember(member, Self.accessors)
  }

  func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors)
  }

  var debugDescription: String { "<Skill \(ref)>" }

  func match(_ tokens: ArraySlice<String>) -> MatchQuality {
    return name?.match(tokens) ?? .none
  }
}

// MARK: - Gender

enum Gender: Codable, ValueRepresentableEnum {
  case male, female

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })
}

// MARK: - Avatar

final class Avatar: PhysicalEntity {
  var level = 1

  // Experience gained toward next level.
  var xp = 0

  var race: Race?
  var gender: Gender?
  var name: String?

  var inventory = ItemCollection()

  // Equipped items.
  var equipped = [EquipmentSlot:Equipment]()

  // A mapping from identifiers of active quests to their current state.
  var activeQuests = [Ref:QuestState]()

  // A mapping from identifiers of completed quests to the time of completion.
  var completedQuests = [Ref:Int]()

  // Karma available to learn skills.
  var karma = 0

  // Current rank in all known skills.
  var skills = [Ref:Int]()

  // Tutorials.
  var tutorialsOn = true
  var tutorialsSeen = Set<String>()

  // Properties below this point are not encoded/decoded.

  var accountID: AccountID!

  // Pending offer, if any.
  var offer: Offer?

  // Current activity, if any.
  var activity: Activity?

  // Cached copy of last map displayed to the player.
  var map: Map?

  // Open WebSocket used to communicate with the client.
  var handler: WebSocketHandler?

  private static let accessors = [
    "level": Accessor(readOnly: \Avatar.level),
    "xp": Accessor(readOnly: \Avatar.xp),
    "race": Accessor(\Avatar.race),
    "gender": Accessor(\Avatar.gender),
    "name": Accessor(\Avatar.name),
    "location": Accessor(readOnly: \Avatar.location),
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }

  override func describeBriefly(_ format: Text.Format) -> String {
    name ?? race?.describeBriefly(format) ?? super.describeBriefly(format)
  }

  static let karmaPerLevel = 10

  func xpRequiredForNextLevel() -> Int {
    1000 + level * (level - 1) * 500
  }

  func gainXP(_ amount: Int) {
    show("You gain \(amount) experience.")
    xp += amount
    let required = xpRequiredForNextLevel()
    var update = AvatarProperties()
    if xp >= required {
      level += 1
      xp -= required
      showNotice("You are now level \(level)!")
      show("You gain \(Self.karmaPerLevel) karma.")
      karma += Self.karmaPerLevel

      // TODO: update karma on skills pane
      update.xp = xp
      update.maxXP = xpRequiredForNextLevel()
    } else {
      update.xp = xp
    }
    updateSelf(update)
  }
}

// MARK: - as Codable

extension Avatar: Codable {
  enum CodingKeys: CodingKey {
    case location, level, xp, race, gender, name, inventory, equipped
    case activeQuests, completedQuests, karma, skills, tutorialsOn, tutorialsSeen
  }

  convenience init(from decoder: Decoder) throws {
    self.init(prototype: World.instance.avatarPrototype)
    copyProperties(from: World.instance.avatarPrototype)

    let c = try decoder.container(keyedBy: CodingKeys.self)

    let locationRef = try c.decode(Ref.self, forKey: .location)
    if let loc = World.instance.lookup(locationRef, context: nil)?.asEntity(Location.self) {
      self.container = loc
    } else {
      logger.warning("cannot find location \(locationRef), using start location")
      self.container = World.instance.startLocation
    }

    level = try c.decode(Int.self, forKey: .level)
    xp = try c.decode(Int.self, forKey: .xp)

    if let raceRef = try c.decodeIfPresent(Ref.self, forKey: .race) {
      if case let .race(race) = World.instance.lookup(raceRef, context: nil) {
        self.race = race
      } else {
        logger.warning("cannot find race \(raceRef)")
      }
    } else {
      logger.warning("avatar has no race")
    }

    gender = try c.decode(Gender?.self, forKey: .gender)
    name = try c.decode(String?.self, forKey: .name)
    inventory = try c.decode(ItemCollection.self, forKey: .inventory)
    equipped = try c.decode([EquipmentSlot:Equipment].self, forKey: .equipped)
    activeQuests = try c.decode([Ref:QuestState].self, forKey: .activeQuests)
    completedQuests = try c.decode([Ref:Int].self, forKey: .completedQuests)
    if let karma = try? c.decodeIfPresent(Int.self, forKey: .karma) {
      self.karma = karma
    }
    skills = try c.decode([Ref:Int].self, forKey: .skills)

    tutorialsOn = try c.decode(Bool.self, forKey: .tutorialsOn)
    tutorialsSeen = try c.decode(Set<String>.self, forKey: .tutorialsSeen)
  }

  func encode(to encoder: Encoder) throws {
    // case location, level, race, gender, name, inventory, equipped
    // case activeQuests, completedQuests, skills, tutorialsOn, tutorialsSeen
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(location.ref, forKey: .location)
    try c.encode(level, forKey: .level)
    try c.encode(xp, forKey: .xp)
    try c.encode(race?.ref, forKey: .race)
    try c.encode(gender, forKey: .gender)
    try c.encode(name, forKey: .name)
    try c.encode(inventory, forKey: .inventory)
    try c.encode(equipped, forKey: .equipped)
    try c.encode(activeQuests, forKey: .activeQuests)
    try c.encode(completedQuests, forKey: .completedQuests)
    try c.encode(karma, forKey: .karma)
    try c.encode(skills, forKey: .skills)
    try c.encode(tutorialsOn, forKey: .tutorialsOn)
    try c.encode(tutorialsSeen, forKey: .tutorialsSeen)
  }

  static let saveInterval = 60.0

  func savePeriodically() {
    World.schedule(delay: Self.saveInterval) { [weak self] in
      if let self = self {
        logger.debug("saving avatar for account \(self.accountID!)")
        _ = World.instance.db.saveAvatar(accountID: self.accountID, avatar: self)
        self.savePeriodically()
      }
    }
  }
}

// MARK: - as WebSocketDelegate

extension Avatar: WebSocketDelegate {
  func onOpen(_ handler: WebSocketHandler) {
    let reconnecting = self.handler != nil
    self.handler = handler

    if reconnecting {
      showNotice("Welcome back!")
      locationChanged()
    } else {
      showNotice("Welcome to Atalea!")

      // FIXME: figure out a portal to use.
      triggerEvent("enterLocation", in: location, participants: [self],
                   args: [self, location]) {
        location.insert(self)
        locationChanged()
      }

      savePeriodically()
    }

    // FIXME: updateInventory(inventory.stacks)
    updateEquipment(equipped.keys)

    var update = AvatarProperties()
    update.xp = xp
    update.maxXP = xpRequiredForNextLevel()
    updateSelf(update)
  }

  func onClose(_ handler: WebSocketHandler) {
    self.handler = nil
  }

  func onReceiveMessage(_ handler: WebSocketHandler, _ message: String) {
    Command.processInput(actor: self, input: message)
  }
}

// MARK: - sending client messages

struct Message<Arg: Encodable>: Encodable {
  let fn: String
  let args: [Arg]
}

extension Avatar {

  func sendMessage(_ fn: String, _ args: ClientValue...) {
    if let handler = handler {
      let encoder = JSONEncoder()
      let data = try! encoder.encode(ClientCall(fn: fn, args: args))
      handler.sendTextMessage(String(data: data, encoding: .utf8)!)
    }
  }

  func sendMessage<Arg: Encodable>(_ fn: String, _ args: [Arg]) {
    if let handler = handler {
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      let data = try! encoder.encode(Message(fn: fn, args: args))
      handler.sendTextMessage(String(data: data, encoding: .utf8)!)
    }
  }

  func show(_ message: String) {
    sendMessage("showText", .string(message))
  }

  func showNotice(_ message: String) {
    sendMessage("showNotice", .string(message))
  }

  func showSay(_ actor: PhysicalEntity, _ verb: String, _ message: String, _ isChat: Bool) {
    sendMessage("showSay",
                .string(actor.describeBriefly([.capitalized, .definite])),
                .string(verb),
                .string(message),
                .boolean(isChat))
  }

  func locationChanged() {
    showMap()
    setNeighbors()
    describeLocation()
    if let tutorial = location.tutorial, let key = location.ref?.description {
      showTutorial(key, tutorial)
    }
  }

  func showTutorial(_ key: String, _ message: String) {
    if tutorialsOn && tutorialsSeen.insert(key).inserted {
      sendMessage("showTutorial", .string(message))
    }
  }

  func describeLocation() {
    let exits = location.exits.filter{ $0.isObvious(to: self) }
      .map { ClientValue.string(String(describing: $0.direction)) }

    let contents = location.contents.filter { $0 != self && $0.isObvious(to: self) }
      .map {
        ClientValue.list([.integer($0.id),
                          .string($0.describeBriefly([.capitalized, .indefinite])),
                          .string($0.describePose())])
      }

    sendMessage("showLocation",
                .string(location.name),
                .string(location.description),
                .list(exits),
                .list(contents))
  }

  func showLinks(_ heading: String, _ prefix: String, _ links: [String]) {
    sendMessage("showLinks", .string(heading), .string(prefix),
                .list(links.map { ClientValue.string($0) }))
  }

  func showList(_ heading: String, _ items: [String]) {
    sendMessage("showList", .string(heading), .list(items.map { ClientValue.string($0) }))
  }
}

// MARK: - look command

let lookCommand = Command("look at:target with|using|through:tool") { actor, verb, clauses in
  if case let .tokens(target) = clauses[0] {
    guard let targetMatch = match(target,
                                  against: actor.location.contents, actor.location.exits,
                                  where: { $0.isVisible(to: actor) }) else {
      actor.show("You don't see anything like that here.")
      return
    }

    // TODO: using tool

    for target in targetMatch {
      actor.show(target.describeFully())
    }
  } else {
    if case let .tokens(tool) = clauses[1] {
      // TODO:
    } else {
      actor.describeLocation()
    }
  }
}

// MARK: - talk command

let talkCommand = Command("talk to:target about:topic") { actor, verb, clauses in
  var candidates = actor.location.contents.filter {
    $0.isVisible(to: actor) && $0.canRespondTo(phase: .when, event: "talk")
  }

  if case let .tokens(targetPhrase) = clauses[0] {
    guard let matches = match(targetPhrase, against: candidates) else {
      actor.show("There's nobody like that here to talk to.")
      return
    }
    candidates = matches.matches
  } else if candidates.isEmpty {
    actor.show("There's nobody here to talk to.")
    return
  }

  if candidates.count > 1 {
    actor.show("Do you want to talk to \(candidates.describe(using: "or"))?")
    return
  }

  triggerEvent("talk", in: actor.location, participants: [actor, candidates[0]],
               args: [actor, candidates[0], clauses[1].asString]) {}
}

// MARK: - tutorial command

let tutorialHelp = """
Use the `tutorial` command to control how you see tutorial messages associated
with locations or actions. Tutorials are used to introduce new players to game
concepts and commands.

The command can be used in several ways:

- Type `tutorial` to see the tutorial associated with the current location, if any.

- Type `tutorial off` to disable display of tutorials.

- Type `tutorial on` to re-enable display of tutorials. Tutorials are on by default.

- Type `tutorial reset` to clear your memory of the tutorials you've already
seen. You will see them again the next time you encounter them.
"""

let tutorialCommand = Command("tutorial 1:subcommand", help: tutorialHelp) { actor, verb, clauses in
  if case let .string(subcommand) = clauses[0] {
    switch subcommand {
    case "on":
      actor.tutorialsOn = true
      actor.show("Tutorials are enabled.")
    case "off":
      actor.tutorialsOn = false
      actor.show("Tutorials are disabled.")
    case "reset":
      actor.tutorialsSeen = []
      actor.show("Tutorials have been reset.")
    default:
      actor.show("Unrecognized subcommand \"\(subcommand)\".")
    }
  } else {
    if let tutorial = actor.location.tutorial {
      actor.sendMessage("showTutorial", .string(tutorial))
    } else {
      actor.show("There is no tutorial associated with this location.")
    }
  }
}

// MARK: - say command

let sayCommand = Command("say *:message") {
  actor, verb, clauses in
  if case let .string(message) = clauses[0] {
    triggerEvent("say", in: actor.location, participants: [actor], args: [actor, message]) {
      actor.show("You say, \"\(message)\"")
      let speaker = actor.describeBriefly([.capitalized, .indefinite])
      for entity in actor.location.contents {
        if entity != actor, let avatar = entity as? Avatar {
          avatar.show("\(speaker) says, \"\(message)\"")
        }
      }
    }
  } else {
    actor.show("What do you want to say?")
  }
}

// MARK: - save command

let saveCommand = Command("save") {
  actor, verb, clauses in
  if World.instance.db.saveAvatar(accountID: actor.accountID, avatar: actor) {
    actor.show("Your avatar was saved.")
  } else {
    actor.show("Error saving avatar.")
  }
}

// MARK: - use command

let useCommand = Command("use target") { actor, verb, clauses in
  var candidates = actor.location.contents.filter {
    $0.isVisible(to: actor) && $0.canRespondTo(phase: .when, event: "use")
  }

  if case let .tokens(target) = clauses[0] {
    guard let matches = match(target, against: candidates) else {
      actor.show("You don't see anything like that here to use.")
      return
    }
    candidates = matches.matches
  } else if candidates.isEmpty {
    actor.show("There's nothing here that you can use.")
    return
  }

  if candidates.count > 1 {
    actor.show("Do you want to use \(candidates.describe(using: "or"))?")
    return
  }

  triggerEvent("use", in: actor.location, participants: [actor, candidates[0]],
               args: [actor, candidates[0]]) {}
}
