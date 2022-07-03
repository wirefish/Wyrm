//
//  Viewable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Viewable {
    var brief: NounPhrase? { get }
    var pose: String? { get }
    var description: String? { get }
    var icon: String? { get }
}

fileprivate let defaultBrief = NounPhrase("an entity")

extension Viewable {
    func describeBriefly(_ format: Text.Format) -> String {
        (brief ?? defaultBrief).format(quantity: 1, capitalize: format.contains(.capitalized),
                                       article: format.article)
    }
}

