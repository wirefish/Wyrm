//
//  Size.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum Size: ValueRepresentableEnum {
    case tiny, small, medium, large, huge

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}
