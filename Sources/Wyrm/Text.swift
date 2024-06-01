//
//  Text.swift
//  Wyrm
//

struct Text {

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
