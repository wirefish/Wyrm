//
//  Size.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum Size: CaseIterable, ValueRepresentable {
    case tiny, small, medium, large, huge

    static let names = Dictionary(uniqueKeysWithValues: Size.allCases.map {
        (String(describing: $0), $0)
    })

    init?(fromValue value: Value) {
        if let v = Size.enumCase(fromValue: value, names: Size.names) {
            self = v
        } else {
            return nil
        }
    }

    func toValue() -> Value {
        return .symbol(String(describing: self))
    }
}
