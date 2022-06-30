//
//  Fixture.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Fixture: PhysicalEntity, Container {
    // Container
    var size = Size.large
    var capacity = 0
    var contents = [PhysicalEntity]()

    init(withPrototype prototype: Fixture?) {
        if let prototype = prototype {
            size = prototype.size
            capacity = prototype.capacity
            contents = prototype.contents
        }
        super.init(withPrototype: prototype)
    }
}
