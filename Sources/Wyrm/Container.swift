//
//  Container.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Container: AnyObject {
    var size: Size { get }
    var capacity: Int { get }
    var contents: [PhysicalEntity] { get set }
}

extension Container {
    static func combine<T: Entity, U: Entity>(_ t: T, into u: U) -> Bool {
        return false
    }

    static func combine<T: Item, U: Item>(_ t: T, into u: U) -> Bool {
        guard (t.prototype != nil && t.prototype === u.prototype &&
               t.count + u.count <= u.stackLimit) else {
            return false
        }
        u.count += t.count
        return true
    }

    // Attempts to insert an entity into the container, possibly combining it into a
    // stack already within the container. Returns the resulting entity on success or
    // nil if the entity cannot be added because the container is full.
    func insert(_ entity: PhysicalEntity) -> PhysicalEntity? {
        if let stack = contents.first(where: { Self.combine(entity, into: $0) }) {
            return stack
        } else if contents.count < capacity {
            contents.append(entity)
            return entity
        } else {
            return nil
        }
    }

    @discardableResult
    func remove(_ entity: PhysicalEntity) -> Bool {
        guard let index = contents.firstIndex(where: { $0 === entity }) else {
            return false
        }
        contents.remove(at: index)
        return true
    }

    // TODO: func remove(_ item: Item, quantity: Int) -> Item?
}
