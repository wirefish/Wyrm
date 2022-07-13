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

    func canInsert(_ entity: PhysicalEntity) -> Bool {
        return (entity.canInsert(into: self) &&
                (contents.count < capacity ||
                 contents.contains(where: { entity.canMerge(into: $0) })))
    }

    // Attempts to insert an entity into the container, possibly combining it into a
    // stack already within the container. Returns the resulting entity on success or
    // nil if the entity cannot be added because the container is full.
    @discardableResult
    func insert(_ entity: PhysicalEntity) -> PhysicalEntity? {
        if let stack = contents.first(where: { Self.combine(entity, into: $0) }) {
            return stack
        } else if contents.count < capacity {
            contents.append(entity)
            entity.container = self
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
        entity.container = nil
        return true
    }

    @discardableResult
    func remove(_ item: Item, count: Int) -> Item? {
        guard let prototype = item.prototype else {
            return nil
        }

        let candidates: [Item] = contents.compactMap({
            if let item = $0 as? Item, item.prototype === prototype {
                return item
            } else {
                return nil
            }
        }).sorted { $0.count < $1.count }

        var result: Item?
        var countRemaining = count
        var itemsToRemove = [Item]()
        for other in candidates {
            if other.count <= countRemaining {
                itemsToRemove.append(other)
                if result != nil {
                    result!.count += other.count
                } else {
                    result = other
                }
                countRemaining -= other.count
                if countRemaining == 0 {
                    break
                }
            } else {
                result = result ?? other.clone()
                result!.count = countRemaining
                other.count -= countRemaining
                break
            }
        }

        contents = contents.filter { entity in
            itemsToRemove.first(where: { $0 === entity }) == nil
        }
        for item in itemsToRemove {
            item.container = nil
        }

        return result
    }
}
