//
//  File.swift
//  Wyrm
//

struct Text {
    struct Format {
        let capitalized: Bool
        let article: Article
    }

    struct Segment {
        let expr: ParseNode
        let format: Format
        let suffix: String
    }

    let prefix: String
    let segments: [Segment]

    var isLiteral: Bool { segments.isEmpty }
}
