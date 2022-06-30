//
//  Portal.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum PortalState { case open, closed, locked }

protocol Traversable {
    var size: Size { get}
    var isCloseable: Bool { get }
    var lockableWith: Entity? { get }
    var state: PortalState { get set }
}

class Portal: PhysicalEntity, Traversable {
    // Traversable
    var size = Size.large
    var isCloseable = false
    var lockableWith: Entity?
    var state = PortalState.open

    override func copyProperties(from other: Entity) {
        let other = other as! Portal
        size = other.size
        isCloseable = other.isCloseable
        lockableWith = other.lockableWith
        state = other.state
        super.copyProperties(from: other)
    }

    static let accessors = [
        "is_closeable": accessor(\Portal.isCloseable),
    ]

    override subscript(member: String) -> Value? {
        get { return Portal.accessors[member]?.get(self) ?? super[member] }
        set {
            if let acc = Portal.accessors[member] {
                acc.set(self, newValue!)
            } else {
                super[member] = newValue
            }
        }
    }
}

