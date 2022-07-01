//
//  Phrase.swift
//  Wyrm
//
//  Created by Craig Becker on 5/26/22.
//

func trimmed(_ s: String) -> Substring {
    if let first = s.firstIndex(where: { !$0.isWhitespace }),
       let last = s.lastIndex(where: { !$0.isWhitespace }) {
        return s[first...last]
    } else {
        return Substring()
    }
}

func capitalized(_ s: String) -> String {
    return s.prefix(1).uppercased() + s.dropFirst()
}

func splitArticle(_ s: Substring) -> (String, Substring) {
    if s.hasPrefix("a ") {
        return ("a", s.dropFirst(2))
    } else if s.hasPrefix("an ") {
        return ("an", s.dropFirst(3))
    } else if s.hasPrefix("the ") {
        return ("the", s.dropFirst(4))
    } else {
        return ("aeiou".contains(s.first!) ? "an" : "a", s)
    }
}

func guessPluralNoun(_ s: Substring) -> String {
    if let ult = s.last {
        if ult == "y" {
            if let penult = s.dropLast().last {
                if !"aeiou".contains(penult) {
                    return String(s.dropLast()) + "ies"
                }
            }
        } else if "sxzo".contains(ult) || s.hasSuffix("ch") || s.hasSuffix("sh") {
            return s + "es"
        }
    }
    return String(s) + "s"
}

func parsePluralRule(_ rule: Substring) -> (Substring, Substring) {
    if let sep = rule.firstIndex(of: "|") {
        return (rule[..<sep], rule[rule.index(after: sep)...])
    } else {
        return (Substring(), rule)
    }
}

func applyPluralRule(_ s: Substring) -> (String, String) {
    if let start = s.firstIndex(of:"[") {
        let prefix = s[..<start]
        var suffix = s[s.index(after: start)...]
        if let end = suffix.firstIndex(of:"]") {
            // Appears to be a valid plural rule.
            let rule = suffix[..<end]
            suffix = suffix[suffix.index(after: end)...]
            let (singular, plural) = parsePluralRule(rule)
            return (String(prefix) + singular + suffix,
                    String(prefix) + plural + suffix)
        }
    }
    return (String(s), guessPluralNoun(s))
}

enum Article {
    case none, indefinite, definite
}

struct NounPhrase: Codable {
    let article: String?
    let singular: String
    let plural: String

    init(_ rawPhrase: String) {
        var phrase = trimmed(rawPhrase)
        if phrase.isEmpty {
            (article, singular, plural) = (nil, "", "")
        } else if phrase.first!.isUppercase {
            // A proper noun.
            article = nil
            singular = String(phrase)
            plural = String(phrase)
        } else {
            (article, phrase) = splitArticle(phrase)
            (singular, plural) = applyPluralRule(phrase)
        }
    }
    
    func format(quantity: Int = 1, capitalize: Bool = false, article: Article = .indefinite) -> String {
        if self.article == nil {
            return singular
        } else if quantity > 1 {
            return "\(quantity) \(plural)"
        } else if quantity == 0 {
            return capitalize ? capitalized(plural) : plural
        } else if article == .none {
            return capitalize ? capitalized(singular) : singular
        } else {
            var out = article == .definite ? "the" : self.article!
            out += " "
            out += singular
            return capitalize ? capitalized(out) : out
        }
    }
}
