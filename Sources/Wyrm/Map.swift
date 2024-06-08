//
//  Map.swift
//  Wyrm
//

class Map {
  struct Cell {
    let location: Location
    let offset: (x: Int, y: Int)
  }

  let radius: Int
  var cells: [Cell]

  init(at startLocation: Location, radius: Int = 3) {
    self.radius = radius
    cells = [Cell(location: startLocation, offset: (0, 0))]
    var seen: Set<Location> = [startLocation]
    var nextOpen = 0
    while nextOpen < cells.count {
      let cell = cells[nextOpen]; nextOpen += 1
      if cell.location.domain != startLocation.domain {
        continue
      }
      for portal in cell.location.exits {
        guard let destination = portal.destination else {
          continue
        }
        if seen.insert(destination).inserted {
          let (x, y, z) = portal.direction.offset
          if z == 0 && (x != 0 || y != 0) && abs(cell.offset.x + x) <= radius &&
              abs(cell.offset.y + y) <= radius {
            cells.append(Cell(location: destination,
                              offset: (x + cell.offset.x, y + cell.offset.y)))
          }
        }
      }
    }
  }
}

extension Avatar {
  // Bits in the location state sent to the client. Lower bits are derived from
  // the raw values of the exit directions.
  static let questAvailableBit = 1 << 12
  static let questAdvanceableBit = 1 << 13
  static let questCompletableBit = 1 << 14
  static let vendorBit = 1 << 15
  static let trainerBit = 1 << 16

  func mapUpdate() -> ClientUpdate {
    let map = Map(at: location)

    let cells = map.cells.map { cell -> ClientUpdate.MapCell in
      var flags = 0
      for portal in cell.location.exits {
        flags |= (1 << portal.direction.rawValue)
      }
      for entity in cell.location.contents {
        // TODO: quest state
        if let creature = entity as? Creature {
          if creature.sells != nil { flags |= ClientUpdate.MapCell.vendor }
          if creature.teaches != nil { flags |= ClientUpdate.MapCell.trainer }
        }
      }
      return ClientUpdate.MapCell(
        key: cell.location.id,
        x: cell.offset.x,
        y: cell.offset.y,
        icon: nil,  // FIXME: add icon
        flags: flags
        // FIXME: add surface, surround, domain
      )
    }

    return .setMap(
      region: location.region?.name ?? "",
      subregion: location.subregion,
      location: location.name,
      radius: map.radius,
      cells: cells)
  }

  func showMap() {
    let map = Map(at: location)
    sendMessage("showMap",
                .string(location.name),
                .string(location.region?.name ?? ""),
                .string(location.subregion),
                .integer(map.radius),
                .list(map.cells.map { cell -> ClientValue in

                  var state = 0
                  for portal in cell.location.exits {
                    state |= (1 << portal.direction.rawValue)
                  }

                  for entity in cell.location.contents {
                    if let entity = entity as? Questgiver {
                      if entity.completesQuestFor(self) {
                        state |= Self.questCompletableBit
                      } else if entity.advancesQuestFor(self) {
                        state |= Self.questAdvanceableBit
                      } else if entity.offersQuestFor(self) {
                        state |= Self.questAvailableBit
                      }
                    }
                    if let creature = entity as? Creature {
                      if creature.sells != nil {
                        state |= Self.vendorBit
                      }
                      if creature.teaches != nil {
                        state |= Self.trainerBit
                      }
                    }
                  }

                  return .list([.integer(cell.location.id),
                                .integer(cell.offset.x),
                                .integer(cell.offset.y),
                                .string(cell.location.name),
                                .string(nil),  // FIXME: icon
                                .integer(state),
                                .string(cell.location.surface),
                                .string(nil),  // FIXME: surrounding
                                .string(cell.location.domain)])
                }))
    self.map = map
  }
}
