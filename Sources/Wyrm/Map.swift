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
  func mapUpdate() -> ClientUpdate {
    let map = Map(at: location)
    self.map = map

    let cells = map.cells.map { cell -> ClientUpdate.MapCell in
      var state = 0
      for portal in cell.location.exits {
        state |= (1 << portal.direction.rawValue)
      }
      for entity in cell.location.contents {
        if let entity = entity as? Questgiver {
          if entity.completesQuestFor(self) {
            state |= ClientUpdate.MapCell.questCompletable
          } else if entity.advancesQuestFor(self) {
            state |= ClientUpdate.MapCell.questAdvanceable
          } else if entity.offersQuestFor(self) {
            state |= ClientUpdate.MapCell.questAvailable
          }
        }
        if let creature = entity as? Creature {
          if creature.sells != nil { state |= ClientUpdate.MapCell.vendor }
          if creature.teaches != nil { state |= ClientUpdate.MapCell.trainer }
        }
      }
      return ClientUpdate.MapCell(
        key: cell.location.id,
        x: cell.offset.x,
        y: cell.offset.y,
        name: cell.location.name,
        state: state,
        icon: nil,  // FIXME: add icon
        domain: cell.location.domain,
        surface: cell.location.surface,
        surround: nil  // FIXME: add surround
      )
    }

    return .setMap(
      region: location.region?.name ?? "",
      subregion: location.subregion,
      location: location.name,
      radius: map.radius,
      cells: cells)
  }

  func redrawMap() {
    updateClient(mapUpdate())
  }
}
