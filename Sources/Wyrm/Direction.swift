//
//  Direction.swift
//  Wyrm
//

enum Direction: Int, ValueRepresentableEnum {
  case north = 0, northeast, east, southeast, south, southwest, west, northwest
  case up, down, `in`, out

  var opposite: Direction {
    switch self {
    case .north: return .south
    case .northeast: return .southwest
    case .east: return .west
    case .southeast: return .northwest
    case .south: return .north
    case .southwest: return .northeast
    case .west: return .east
    case .northwest: return .southeast
    case .up: return .down
    case .down: return .up
    case .in: return .out
    case .out: return .in
    }
  }

  var offset: (Int, Int, Int) {
    switch self {
    case .north: return (0, -1, 0)
    case .northeast: return (1, -1, 0)
    case .east: return (1, 0, 0)
    case .southeast: return (1, 1, 0)
    case .south: return (0, 1, 0)
    case .southwest: return (-1, 1, 0)
    case .west: return (-1, 0, 0)
    case .northwest: return (-1, -1, 0)
    case .up: return (0, 0, 1)
    case .down: return (0, 0, -1)
    case .in: return (0, 0, 0)
    case .out: return (0, 0, 0)
    }
  }

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })
}

extension Direction: Matchable {
  // FIXME: allow abbreviations like 'sw' for 'southwest'.
  func match(_ tokens: ArraySlice<String>) -> MatchQuality {
    if tokens.count == 1, let token = tokens.first {
      let name = String(describing: self)
      if token == name {
        return .exact
      } else if name.hasPrefix(token) {
        return .partial
      }
    }
    return .none
  }
}
