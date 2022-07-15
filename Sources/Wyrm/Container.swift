//
//  Container.swift
//  Wyrm
//

class Container: PhysicalEntity {
    var capacity = 0
    var contents = [Item]()

    var isFull: Bool { contents.count >= capacity }
}

extension Container {
    // Returns true if count of item can be inserted into the container.
    func canInsert(_ item: Item, count: Int? = nil) -> Bool {
        if let stack = contents.first(where: { item.isStackable(with: $0) }) {
            return (count ?? item.count) + stack.count <= stack.stackLimit
        } else {
            return !isFull
        }
    }

    // Inserts count of item into the container and returns the contained item,
    // which may be item itself or a stack into which the inserted portion of
    // item was merged. If the return value is not item, item's count is
    // modified to represent the remaining, un-inserted portion.
    @discardableResult
    func insert(_ item: Item, count: Int? = nil) -> Item? {
        let count = count ?? item.count
        if let stack = contents.first(where: { item.isStackable(with: $0) }) {
            if count + stack.count <= stack.stackLimit {
                item.count -= count
                stack.count += count
                return stack
            } else {
                return nil
            }
        } else if !isFull {
            if count == item.count {
                contents.append(item)
                item.container = self
                return item
            } else {
                let stack = item.clone()
                stack.count = count
                item.count -= count
                contents.append(stack)
                stack.container = self
                return stack
            }
        } else {
            return nil
        }
    }

    @discardableResult
    func remove(_ item: Item, count: Int? = nil) -> Item? {
        guard let index = contents.firstIndex(of: item) else {
            return nil
        }
        let count = (count ?? item.count)
        if count >= item.count {
            contents.remove(at: index)
            item.container = nil
            return item
        } else {
            let removed = item.clone()
            removed.count = count
            item.count -= count
            return removed
        }
    }
}
