//
//  File.swift
//  Wyrm
//

struct Text {
    struct Format: OptionSet {
        let rawValue: UInt8

        static let capitalized = Format(rawValue: 1 << 0)
        static let indefinite = Format(rawValue: 1 << 1)
        static let definite = Format(rawValue: 1 << 2)
    }

    struct Segment {
        let expr: ParseNode
        let format: Format
        let suffix: String
    }

    let prefix: String
    let segments: [Segment]

    var asLiteral: String? { segments.isEmpty ? prefix : nil }
}
