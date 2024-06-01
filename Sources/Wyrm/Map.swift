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
    guard case let .absolute(moduleName, _) = startLocation.ref,
          let module = World.instance.modules[moduleName] else {
      fatalError("cannot get module from location ref")
    }
    cells = [Cell(location: startLocation, offset: (0, 0))]
    var seen: Set<Location> = [startLocation]
    var nextOpen = 0
    while nextOpen < cells.count {
      let cell = cells[nextOpen]; nextOpen += 1
      if cell.location.domain != startLocation.domain {
        continue
      }
      for portal in cell.location.exits {
        guard let destinationRef = portal.destination,
              let destination = World.instance.lookup(
                destinationRef, context: module)?.asEntity(Location.self) else {
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
