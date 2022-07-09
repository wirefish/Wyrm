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

    init(at startLocation: Location, radius: Int) {
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
