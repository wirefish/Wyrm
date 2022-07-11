//
//  Fixture.swift
//  Wyrm
//
//  Created by Craig Becker on 6/30/22.
//

class Fixture: PhysicalEntity, Container {
    // Container
    var capacity = 0
    var contents = [PhysicalEntity]()

    override func copyProperties(from other: Entity) {
        let other = other as! Fixture
        capacity = other.capacity
        contents = other.contents.map { $0.clone() }
        super.copyProperties(from: other)
    }
}
