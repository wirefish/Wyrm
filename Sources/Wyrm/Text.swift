//
//  File.swift
//  Wyrm
//

struct Text {
    struct Segment {
        let expr: ParseNode
        let format: UInt8
        let suffix: String
    }

    let prefix: String
    let segments: [Segment]

    var asLiteral: String? { segments.isEmpty ? prefix : nil }
}
