//
//  Viewable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

protocol Viewable {
    func isVisible(to observer: Avatar) -> Bool

    func isObvious(to observer: Avatar) -> Bool

    func describeBriefly(_ format: Text.Format) -> String

    func describePose() -> String

    func describeFully() -> String

    var icon: String? { get }
}

extension Sequence where Element: Viewable {
    func describe(using conjunction: String = "and") -> String {
        return map({ $0.describeBriefly([.indefinite]) }).conjunction(using: conjunction)
    }
}
