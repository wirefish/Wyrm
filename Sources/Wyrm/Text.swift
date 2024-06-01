//
//  Text.swift
//  Wyrm
//

struct Text {
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

  enum Segment {
    case string(String)
    case expr(Expression, Format)
  }

  let segments: [Segment]

  var asLiteral: String? {
    if segments.count == 1, case let .string(s) = segments.first {
      return s
    } else {
      return nil
    }
  }
}
