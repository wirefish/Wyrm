//
//  Viewable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Viewable {
    var brief: NounPhrase? { get }
    var pose: VerbPhrase? { get }
    var description: String? { get }
    var icon: String? { get }
}

