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

    struct Segment {
        let expr: ParseNode
        let format: Format
        let suffix: String
    }

    let prefix: String
    let segments: [Segment]

    var asLiteral: String? { segments.isEmpty ? prefix : nil }
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
