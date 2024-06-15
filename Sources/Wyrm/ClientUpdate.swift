//
//  ClientUpdate.swift
//  Wyrm
//

import Foundation

// MARK: ClientUpdate

enum ClientUpdate: Encodable {
  struct Aura: Encodable {
    let type: String
    let icon: String
    let name: String
    let expiry: Int
  }
  
  struct Neighbor: Encodable {
    let key: Int
    let brief: String
    let icon: String?
    let currentHealth, maxHealth: Int?
    
    init(_ entity: Thing) {
      key = entity.id
      brief = entity.describeBriefly([])
      icon = entity.icon
      if let combatant = entity as? Combatant {
        currentHealth = combatant.health
        maxHealth = combatant.maxHealth()
      } else {
        currentHealth = nil
        maxHealth = nil
      }
    }
  }
  
  struct Item: Encodable {
    let key: Int
    let brief: String
    let icon: String?
    
    init(_ stack: ItemStack) {
      key = stack.item.id
      brief = stack.describeBriefly([])
      icon = stack.item.icon
    }
  }
  
  struct Equipment: Encodable {
    let slot: EquipmentSlot
    let brief: String
    let icon: String?
    
    init(slot: EquipmentSlot, item: Wyrm.Equipment) {
      self.slot = slot
      brief = item.describeBriefly([])
      icon = item.icon
    }
  }
  
  struct Skill: Encodable {
    let label: String
    let name: String
    let rank, maxRank: Int
  }

  struct Quest: Encodable {
    let key: String
    let name: String
    let level: Int
    let summary: String
    let progress: Int?
    let required: Int?
  }

  struct Attribute: Encodable {
    let name: String
    let value: Int
  }
  
  struct LocationContent: Encodable {
    let key: Int
    let brief, pose: String
    
    init(_ entity: Thing) {
      key = entity.id
      brief = entity.describeBriefly([.indefinite, .capitalized])
      pose = entity.describePose()
    }
  }
  
  struct MapCell: Encodable {
    // The `state` property encodes exit directions in addition to the following.
    // For an exit direction `dir`, its bit mask is `1 << dir.rawValue`.
    static let questAvailable = 1 << 12
    static let questAdvanceable = 1 << 13
    static let questCompletable = 1 << 14
    static let vendor = 1 << 15
    static let trainer = 1 << 16

    let key: Int
    let x, y: Int
    let name: String
    let state: Int
    let icon: String?
    let domain: String?
    let surface: String?
    let surround: String?
  }
  
  // Avatar
  case setAvatarKey(Int)
  case setAvatarName(String?)
  case setAvatarIcon(String?)
  case setAvatarRace(String?)
  case setAvatarLevel(Int)
  case setAvatarXP(current: Int, max: Int)
  case setAvatarHealth(current: Int, max: Int)
  case setAvatarEnergy(current: Int, max: Int)
  case setAvatarMana(current: Int, max: Int)

  // Neighbors
  case setNeighbors([Neighbor])
  case updateNeighbor(Neighbor)
  case removeNeighbor(key: Int)
  
  // Auras attached to avatar, neighbor, or combatant (based on key)
  case setAuras(key: Int, auras: [Aura])
  case addAura(key: Int, aura: Aura)
  case removeAura(key: Int, type: String)

  // Equipment
  case setEquipment([Equipment])
  case equip(Equipment)
  case unequip(slot: String)
  
  // Inventory
  case setItems([Item])
  case updateItem(Item)
  case removeItem(Int)
  
  // Skills
  case setKarma(Int)
  case setSkills([Skill])
  case updateSkill(Skill)
  case removeSkill(label: String)

  // Attributes
  case setAttributes([Attribute])
  case updateAttribute(Attribute)

  // Quests
  case setQuests([Quest])
  case updateQuest(Quest)
  case removeQuest(key: String)

  // Messages
  case showRaw(String)
  case showText(String)
  case showNotice(String)
  case showTutorial(String)
  case showHelp(String)
  case showError(String)
  case showSay(speaker: String, verb: String, text: String, isChat: Bool)
  case showList(heading: String, items: [String])
  case showLinks(heading: String, prefix: String, topics: [String])
  case showLocation(name: String, description: String, exits: [String], contents: [LocationContent])
  
  // Cast bar attached to avatar, neighbor, or combatant (based on key)
  case startCast(key: Int, duration: Int)
  case stopCast(key: Int)
  
  // Map
  case setMap(region: String, subregion: String?, location: String, radius: Int, cells: [MapCell])
  case updateMap(cells: [MapCell])
}

struct ClientMessage: Encodable {
  let updates: [ClientUpdate]
}

// MARK: Avatar extension

extension Avatar {
  // Adds updates to the set of updates that need to sent to the client. If there are
  // no updates already pending, schedules the updates to be sent on the next pass through
  // the event loop.
  func updateClient(_ updates: ClientUpdate...) {
    if clientUpdates.isEmpty {
      DispatchQueue.main.async { self.sendUpdates() }
    }
    clientUpdates += updates
  }
  
  // Sends all pending updates to the client and clears the list of pending updates.
  private func sendUpdates() {
    if let handler = handler {
      let encoder = JSONEncoder()
      // let data = try! encoder.encode(Message(fn: "update", args: clientUpdates))
      let data = try! encoder.encode(ClientMessage(updates: clientUpdates))
      handler.sendTextMessage(String(data: data, encoding: .utf8)!)
      clientUpdates.removeAll()
    }
  }

  // Updates UI elements that change upon entering a new location.
  func updateForLocation() {
    updateClient(
      // Neighbors
      .setNeighbors(location.contents.compactMap { entity -> ClientUpdate.Neighbor? in
        if (entity != self && !entity.implicit && entity.isVisible(to: self)) {
          ClientUpdate.Neighbor(entity)
        } else {
          nil
        }
      }),
      mapUpdate(),
      locationUpdate())

    if let tutorial = location.tutorial, let key = location.ref?.description {
      showTutorial(key, tutorial)
    }
  }
  
  // Updates all UI elements.
  func updateAll() {
    // TODO: auras, attributes, cast bar?
    updateClient(
      // Avatar
      .setAvatarKey(id),
      .setAvatarName(name), .setAvatarIcon(icon), .setAvatarLevel(level),
      .setAvatarRace(race?.describeBriefly([]) ?? "unknown race"),
      .setAvatarXP(current: xp, max: xpRequiredForNextLevel()),
      // Equipment
      .setEquipment(equipped.map { ClientUpdate.Equipment(slot: $0, item: $1) }),
      // Inventory
      .setItems(inventory.stacks().map { ClientUpdate.Item($0) }),
      // Skills
      .setSkills(skills.compactMap { (ref, rank) -> ClientUpdate.Skill? in
        guard let skill = Skill.fromValue(World.instance.lookup(ref)) else {
          return nil
        }
        return ClientUpdate.Skill(label: skill.ref.name,
                                  name: skill.name ?? "unnamed skill",
                                  rank: rank, maxRank: skill.maxRank)
      }))
    updateForLocation()
  }

  func locationUpdate() -> ClientUpdate {
    let exits = location.exits.compactMap {
      (!$0.implicit && $0.isVisible(to: self)) ? String(describing: $0.direction) : nil
    }
    let contents = location.contents.compactMap {
      ($0 != self && !$0.implicit && $0.isVisible(to: self)) ? ClientUpdate.LocationContent($0) : nil
    }
    return .showLocation(name: location.name, description: location.description,
                         exits: exits, contents: contents)
  }

  func describeLocation() {
    updateClient(locationUpdate())
  }

  func show(_ message: String) {
    updateClient(.showText(message))
  }

  func showNotice(_ message: String) {
    updateClient(.showNotice(message))
  }

  func showTutorial(_ key: String, _ message: String) {
    if tutorialsOn && tutorialsSeen.insert(key).inserted {
      dirtyTutorials.append(key)
      updateClient(.showTutorial(message))
    }
  }

  func showSay(_ speaker: Thing, _ verb: String, _ message: String, _ isChat: Bool = false) {
    updateClient(.showSay(speaker: speaker.describeBriefly([.capitalized, .definite]),
                          verb: verb, text: message, isChat: isChat))
  }

  func showList(_ heading: String, _ items: [String]) {
    updateClient(.showList(heading: heading, items: items))
  }

  func showLinks(_ heading: String, _ prefix: String, _ topics: [String]) {
    updateClient(.showLinks(heading: heading, prefix: prefix, topics: topics))
  }

  func removeNeighbor(_ entity: Thing) {
    updateClient(.removeNeighbor(key: entity.id))
  }

  func updateNeighbor(_ entity: Thing) {
    updateClient(.updateNeighbor(ClientUpdate.Neighbor(entity)))
  }
}
