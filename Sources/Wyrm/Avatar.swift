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
    "brief": Accessor(writeOnly: \Race.brief),
    "description": Accessor(\Race.description),
  ]

  func get(_ member: String) -> Value? {
    getMember(member, Self.accessors)
  }

  func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors)
  }

  func describeBriefly(_ format: Format) -> String {
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
  var currencyPrice: ItemStack?
  var requiredSkills: [Skill]?
  var exclusiveSkills: [Skill]?

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

final class Avatar: Thing {
  var level = 1 {
    didSet { updateClient(.setAvatarLevel(level)) }
  }

  // Experience gained toward next level.
  var xp = 0 {
    didSet { updateClient(.setAvatarXP(current: xp, max: xpRequiredForNextLevel())) }
  }

  var race: Race? {
    didSet { updateClient(.setAvatarRace(race!.describeBriefly([]))) }
  }
  
  var name: String? {
    didSet { updateClient(.setAvatarName(name!)) }
  }

  var gender: Gender?

  var inventory = ItemCollection()

  // Equipped items.
  var equipped = [EquipmentSlot:Equipment]()

  // A mapping from identifiers of active quests to their current state.
  var activeQuests = [Ref:QuestState]()

  // Karma available to learn skills.
  var karma = 0 {
    didSet { updateClient(.setKarma(karma)) }
  }

  // Current rank in all known skills.
  var skills = [Ref:Int]()

  // Show tutorials?
  var tutorialsOn = true

  //
  // Properties in this section are persisted separately. Since they tend to grow
  // without bound over time, only updated values are written to the database when
  // saving the avatar.
  //

  // Refs of tutorials that have been seen.
  var tutorialsSeen = Set<String>()
  var dirtyTutorials = [String]()

  // A mapping from identifiers of completed quests to the time of completion.
  var completedQuests = [Ref:Int]()
  var dirtyQuests = [(Ref, Int)]()

  //
  // Properties below this point are not persisted.
  //

  var accountID: AccountID!
  var avatarID: AvatarID!

  // Pending offer, if any.
  var offer: Offer?

  // Current activity, if any.
  var activity: Activity?

  // Cached copy of last map displayed to the player.
  var map: Map?

  // Open WebSocket used to communicate with the client.
  var handler: WebSocketHandler?
  
  // Updates that need to be sent to the client.
  var clientUpdates = [ClientUpdate]()
  
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

  override func describeBriefly(_ format: Format) -> String {
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
    case activeQuests, karma, skills, tutorialsOn
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
    self.karma = try c.decode(Int.self, forKey: .karma)
    skills = try c.decode([Ref:Int].self, forKey: .skills)
    tutorialsOn = try c.decode(Bool.self, forKey: .tutorialsOn)
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
    try c.encode(karma, forKey: .karma)
    try c.encode(skills, forKey: .skills)
    try c.encode(tutorialsOn, forKey: .tutorialsOn)
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
    } else {
      showNotice("Welcome to Atalea!")

      // FIXME: figure out a portal to use.
      triggerEvent("enterLocation", in: location, participants: [self],
                   args: [self, location]) {
        location.insert(self)
      }

      savePeriodically()
    }

    updateAll()
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

  func locationChanged() {
    updateForLocation()
  }
}

// MARK: - look command

let lookCommand = Command("look at:target with|using|through:tool") { actor, verb, clauses in
  if case let .tokens(target) = clauses[0] {
    guard let targetMatch = match(target,
                                  against: actor.location.contents, [Thing](actor.location.exits),
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
    $0.isVisible(to: actor) && $0.canRespondTo(Event(phase: .when, name: "talk"))
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
    $0.isVisible(to: actor) && $0.canRespondTo(Event(phase: .when, name: "use"))
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
