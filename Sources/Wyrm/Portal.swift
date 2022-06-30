//
//  Portal.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

protocol Traversable {
    var size: Size { get}
    var isCloseable: Bool { get }
    var lockableWith: Entity? { get }
    var isClosed: Bool { get }
    var isLocked: Bool { get }
}

class Portal: PhysicalEntity, Traversable {
    // Traversable
    var size = Size.large
    var isCloseable = false
    var lockableWith: Entity?
    var isClosed = false
    var isLocked = false

    init(withPrototype prototype: Portal?) {
        super.init(withPrototype: prototype)
    }

    override func clone() -> Entity {
        return Portal(withPrototype: self)
    }

    static let accessors = [
        "is_closeable": accessor(\Portal.isCloseable),
        "is_closed": accessor(\Portal.isClosed),
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
