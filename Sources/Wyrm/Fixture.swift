//
//  Fixture.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Fixture: Entity, Viewable, Matchable, Container {
    // Viewable
    var brief: NounPhrase?
    var pose: VerbPhrase?
    var description: String?
    var icon: String?

    // Matchable
    var alts = [NounPhrase]()

    // Container
    let size = Size.large
    let capacity = 0
    var contents = [Entity]()
}
