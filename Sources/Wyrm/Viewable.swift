//
//  Viewable.swift
//  Wyrm
//

struct Format: OptionSet {
  let rawValue: UInt8

  static let capitalized = Format(rawValue: 1 << 0)
  static let indefinite = Format(rawValue: 1 << 1)
  static let definite = Format(rawValue: 1 << 2)
  static let plural = Format(rawValue: 1 << 3)
  static let noQuantity = Format(rawValue: 1 << 4)

  var article: Article {
    contains(.definite) ? .definite : (contains(.indefinite) ? .indefinite : .none)
  }
}

// A protocol adopted by objects that can be seen, inspected, etc. by an observer.
protocol Viewable {
  // Returns true if the object is visible to the observer.
  func isVisible(to observer: Avatar) -> Bool

  // Set to true if the object should be excluded from being shown as a member
  // of the contents of the observer's location.
  var implicit: Bool { get }

  // Returns a brief description of the object, e.g. "a ball of string".
  func describeBriefly(_ format: Format) -> String

  // Returns the pose of the object as seen by an observer at the same location,
  // e.g. "is leaning against the wall."
  func describePose() -> String

  // Returns one or more paragraphs describing the object in detail.
  func describeFully() -> String

  // The name of the icon associated with the object, if any.
  var icon: String? { get }
}

extension Viewable {
  func isVisible(to observer: Avatar) -> Bool { true }
  var implicit: Bool { false }
  func describePose() -> String { "is here." }
  func describeFully() -> String {
    "\(self.describeBriefly([.capitalized, .definite])) is unremarkable."
  }
  var icon: String? { nil }
}

extension Array where Element: StringProtocol {
  func conjunction(using word: String) -> String {
    switch count {
    case 0: return ""
    case 1: return String(first!)
    case 2: return "\(first!) \(word) \(last!)"
    default: return "\(dropLast().joined(separator: ", ")), \(word) \(last!)"
    }
  }
}

extension Sequence where Element: Viewable {
  func describe(using conjunction: String = "and") -> String {
    return map({ $0.describeBriefly([.indefinite]) }).conjunction(using: conjunction)
  }
}
