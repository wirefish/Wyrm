//
//  InterpolatedString.swift
//  Wyrm
//

struct InterpolatedString {
  enum Segment {
    case string(String)
    case expr(Expression, Format)
  }

  let segments: [Segment]
}
