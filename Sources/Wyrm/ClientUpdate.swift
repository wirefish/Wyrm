//
//  ClientUpdate.swift
//  Wyrm
//

import Foundation

enum ClientUpdate: Encodable {
  struct Aura: Encodable {
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
      if let health = (entity as? Combatant)?.health {
        currentHealth = health.value
        maxHealth = health.maxValue
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
    let name: String
    let rank, maxRank: Int
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
    // The `flags` property encodes exit directions in addition to the following.
    // For an exit direction `dir`, its bit mask is `1 << dir.rawValue`.
    static let questAvailable = 1 << 16
    static let questAdvanceable = 1 << 17
    static let questCompletable = 1 << 18
    static let vendor = 1 << 19
    static let trainer = 1 << 20

    let key: Int
    let x, y: Int
    let icon: String?
    let flags: Int
  }
  
  // Avatar
  case key(Int)
  case name(String?), icon(String?), race(String?)
  case level(Int)
  case xp(current: Int, max: Int)
  case health(current: Int, max: Int)
  case energy(current: Int, max: Int)
  case mana(current: Int, max: Int)
  
  // Neighbors
  case setNeighbors([Neighbor])
  case updateNeighbor(Neighbor)
  case removeNeighbor(key: Int)
  
  // Auras (for avatar, neighbors, combatants based on key)
  case setAuras(key: Int, [Aura])
  case addAura(key: Int, Aura)
  case removeAura(key: Int, String)
  
  // Equipment
  case setEquipment([Equipment])
  case equip(Equipment)
  case unequip(slot: String)
  
  // Inventory
  case setItems([Item])
  case updateItem(Item)
  case removeItem(Int)
  
  // Skills
  case karma(Int)
  case setSkills([Skill])
  case updateSkill(Skill)
  case removeSkill(name: String)
  
  // Attributes
  case setAttributes([Attribute])
  case updateAttribute(Attribute)

  // Messages
  case message(String)
  case notice(String)
  case tutorial(String)
  case help(String)
  case error(String)
  case say(speaker: String, verb: String, text: String, isChat: Bool)
  case list(heading: String, items: [String])
  case links(heading: String, prefix: String, links: [String])
  case location(name: String, description: String, exits: [String], contents: [LocationContent])
  
  // Cast bar
  case startCast(key: Int, duration: Int)
  case stopCast(key: Int)
  
  // Map
  case setMap(region: String, subregion: String?, location: String, radius: Int, cells: [MapCell])
  case updateMap(cells: [MapCell])
}

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
  
  // Updates UI elements that change upon entering a new location.
  func updateForLocation() {
    // TODO: map, neighbor attributes
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
  }
  
  // Updates all UI elements.
  func updateAll() {
    // TODO: auras, attributes, cast bar?
    updateClient(
      // Avatar
      .name(name), .icon(icon), .level(level),
      .race(race?.describeBriefly([]) ?? "unknown race"),
      .xp(current: xp, max: xpRequiredForNextLevel()),
      // Equipment
      .setEquipment(equipped.map { ClientUpdate.Equipment(slot: $0, item: $1) }),
      // Inventory
      .setItems(inventory.stacks().map { ClientUpdate.Item($0) }),
      // Skills
      .setSkills(skills.compactMap { (ref, rank) -> ClientUpdate.Skill? in
        guard let skill = Skill.fromValue(World.instance.lookup(ref)) else {
          return nil
        }
        return ClientUpdate.Skill(name: skill.name ?? "unnamed skill",
                                  rank: rank, maxRank: skill.maxRank)
      }))
    updateForLocation()
  }

  // Sends all pending updates to the client and clears the list of pending updates.
  private func sendUpdates() {
    if let _ = handler {
      sendMessage("update", clientUpdates)
      clientUpdates.removeAll()
    }
  }
}
