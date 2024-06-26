//
//  Extensions.swift
//  Wyrm
//
//  General-purpose extensions of standard library types.
//

extension Sequence {
  // Returns the first non-nil value obtained by applying a transform to the
  // elements of the array.
  func firstMap<T>(_ transform: (Element) -> T?) -> T? {
    for value in self {
      if let transformedValue = transform(value) {
        return transformedValue
      }
    }
    return nil
  }

  func keep(where pred: (Element) -> Bool) -> [Element] {
    compactMap { pred($0) ? $0 : nil }
  }
}

extension StringProtocol {
  // Returns a subsequence where elements matching the predicate have been removed
  // from both ends of the string.
  func trimmed(_ pred: (Element) -> Bool) -> Self.SubSequence {
    if let first = firstIndex(where: { !pred($0) }),
       let last = lastIndex(where: { !pred($0) }) {
      return self[first...last]
    } else {
      return ""
    }
  }

  // Returns the suffix formed by all elements after (but not including) the given index.
  func suffix(after pos: Self.Index) -> Self.SubSequence {
    return suffix(from: index(after: pos))
  }

  func capitalized() -> String {
    return prefix(1).uppercased() + dropFirst()
  }
}

extension RandomAccessCollection where Element: Comparable {
  // Returns the index of the first element in the collection that does not
  // satisfy self[index] < item. The result is undefined if the collection is
  // not sorted in increasing order.
  func lowerBound(for item: Element) -> Index? {
    var lower = startIndex, upper = endIndex
    while lower < upper {
      let mid = index(lower, offsetBy: distance(from: lower, to: upper) / 2)
      if self[mid] == item {
        return mid
      } else if self[mid] < item {
        lower = index(after: mid)
      } else {
        upper = mid
      }
    }
    return lower == endIndex ? nil : lower
  }

  // Returns the index of the specified element using binary search. The
  // result is undefined if the collection is not sorted in increasing order.
  func binarySearch(for item: Element) -> Index? {
    guard let index = lowerBound(for: item), self[index] == item else {
      return nil
    }
    return index
  }
}

extension Double {
  func roundedRandomly() -> Double {
    let k = self.truncatingRemainder(dividingBy: 1.0)
    return self.rounded(Double.random(in: 0..<1) < k ? .up : .down)
  }
}

// The ??= assignment operator performs assignment only if the rhs is non-nil.

precedencegroup OptionalAssignment { associativity: right }

infix operator ??= : OptionalAssignment

public func ??= <T>(variable: inout T, value: T?) {
  if let value = value {
    variable = value
  }
}
