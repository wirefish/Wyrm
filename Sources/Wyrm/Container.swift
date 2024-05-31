//
//  Container.swift
//  Wyrm
//

class Container: PhysicalEntity {
  var capacity = 0
  var contents = [Item]()
}

extension Container: MutableCollection {
  typealias Index = Int

  var startIndex: Int { contents.startIndex }
  var endIndex: Int { contents.endIndex }
  func index(after i: Int) -> Int { i + 1 }

  subscript(position: Int) -> Item {
    get { contents[position] }
    set { contents[position] = newValue }
  }

  subscript(bounds: Range<Index>) -> ArraySlice<Item> {
    get { return contents[bounds] }
    set { contents[bounds] = newValue }
  }

  func remove(from pos: Index) {
    contents.removeLast(contents.count - pos)
  }
}

extension Container {
  var isFull: Bool { contents.count >= capacity }

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
  func insert(_ item: Item, count: Int? = nil, force: Bool = false) -> Item? {
    let count = count ?? item.count
    if let stack = contents.first(where: { item.isStackable(with: $0) }) {
      if count + stack.count <= stack.stackLimit || force {
        item.count -= count
        stack.count += count
        return stack
      } else {
        return nil
      }
    } else if !isFull || force {
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

  // Removes count of item from the container. If count is nil or >= item's
  // count, removes and returns item. Otherwise, reduces the count of item in
  // the container and returns a clone reflecting the removed count.
  @discardableResult
  func remove(_ item: Item, count: Int? = nil) -> Item? {
    guard let index = contents.firstIndex(of: item) else {
      return nil
    }
    let count = count ?? item.count
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
