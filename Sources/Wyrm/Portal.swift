//
//  Portal.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum PortalState: ValueRepresentableEnum {
    case open, closed, locked

    static let names = Dictionary(uniqueKeysWithValues: Self.allCases.map {
        (String(describing: $0), $0)
    })
}

class Portal: PhysicalEntity {
    var size = Size.large
    var isCloseable = false
    var lockableWith: Item?
    var state = PortalState.open
    var twin: Portal?

    override func copyProperties(from other: Entity) {
        let other = other as! Portal
        size = other.size
        isCloseable = other.isCloseable
        lockableWith = other.lockableWith
        state = other.state
        super.copyProperties(from: other)
    }

    static let accessors = [
        "size": accessor(\Portal.size),
        "is_closeable": accessor(\Portal.isCloseable),
        "lockable_with": accessor(\Portal.lockableWith),
        "state": accessor(\Portal.state),
        "twin": accessor(\Portal.twin),
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
