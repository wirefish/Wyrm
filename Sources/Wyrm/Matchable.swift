//
//  Matchable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

protocol Matchable {
    var brief: NounPhrase? { get }
    var alts: [NounPhrase] { get }
}
