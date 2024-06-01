//
//  Size.swift
//  Wyrm
//

enum Size: ValueRepresentableEnum, Comparable {
  case tiny, small, medium, large, huge

  static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
    (String(describing: $0), $0)
  })
}
