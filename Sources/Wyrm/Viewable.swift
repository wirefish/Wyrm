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
