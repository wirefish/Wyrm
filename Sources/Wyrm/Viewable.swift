//
//  Viewable.swift
//  Wyrm
//

protocol Viewable {
  func isVisible(to observer: Avatar) -> Bool

  func isObvious(to observer: Avatar) -> Bool

  func describeBriefly(_ format: Text.Format) -> String

  func describePose() -> String

  func describeFully() -> String

  var icon: String? { get }
}

extension Viewable {
  func isVisible(to observer: Avatar) -> Bool { true }

  func isObvious(to observer: Avatar) -> Bool { true }

  func describePose() -> String { "is here." }

  func describeFully() -> String { "The thing is unremarkable." }

  var icon: String? { nil }
}

extension Sequence where Element: Viewable {
  func describe(using conjunction: String = "and") -> String {
    return map({ $0.describeBriefly([.indefinite]) }).conjunction(using: conjunction)
  }
}
