//
//  Creature.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Creature: Entity, Viewable, Matchable, Attackable {
    // Viewable
    var brief: NounPhrase?
    var pose: VerbPhrase?
    var description: String?
    var icon: String?

    // Matchable
    var alts = [NounPhrase]()

    // Attackable
    var level = 1
    var currentHealth: Int = 1  // FIXME:
    var maxHealth: Int { return 10 + 10 * level }

    init(withPrototype prototype: Creature?) {
        super.init(withPrototype: prototype)
    }

    func defenseAgainst(damageType: DamageType) -> Int { 0 }
}
