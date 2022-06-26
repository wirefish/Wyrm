//
//  Viewable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
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

class Viewable: Facet {
    var name: String?
    var brief: NounPhrase?
    var pose: VerbPhrase?
    var description: String?
    var icon: String?
    var size = Size.medium

    static let isMutable = false

    required init() {
    }

    func clone() -> Facet {
        let v = Viewable()
        v.name = name
        v.brief = brief
        return v
    }

    static let accessors = [
        "name": accessor(\Viewable.name),
        "brief": accessor(\Viewable.brief),
        "pose": accessor(\Viewable.pose),
        "size": accessor(\Viewable.size),
    ]
}

