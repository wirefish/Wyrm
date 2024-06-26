//
//  NounPhrase.swift
//  Wyrm
//

fileprivate func trimmed(_ s: String) -> Substring {
  if let first = s.firstIndex(where: { !$0.isWhitespace }),
     let last = s.lastIndex(where: { !$0.isWhitespace }) {
    return s[first...last]
  } else {
    return Substring()
  }
}

fileprivate func splitArticle(_ s: Substring) -> (String?, Substring) {
  if s.first!.isUppercase {
    return (nil, s)
  } else if s.hasPrefix("a ") {
    return ("a", s.dropFirst(2))
  } else if s.hasPrefix("an ") {
    return ("an", s.dropFirst(3))
  } else if s.hasPrefix("the ") {
    return ("the", s.dropFirst(4))
  } else if s.hasPrefix("_ ") {
    return (nil, s.dropFirst(2))
  } else {
    return ("aeiou".contains(s.first!) ? "an" : "a", s)
  }
}

fileprivate func guessPluralNoun(_ s: Substring) -> String {
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

fileprivate func parsePluralRule(_ rule: Substring) -> (Substring, Substring) {
  if let sep = rule.firstIndex(of: "|") {
    return (rule[..<sep], rule[rule.index(after: sep)...])
  } else {
    return (Substring(), rule)
  }
}

fileprivate func applyPluralRule(_ s: Substring) -> (String, String) {
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

struct NounPhrase {
  let article: String?
  let singular: String
  let plural: String

  init(_ rawPhrase: String) {
    var phrase = trimmed(rawPhrase)
    if phrase.isEmpty {
      (article, singular, plural) = (nil, "", "")
    } else {
      (article, phrase) = splitArticle(phrase)
      if article != nil {
        (singular, plural) = applyPluralRule(phrase)
      } else {
        singular = String(phrase)
        plural = singular
      }
    }
  }

  func format(_ format: Format, count: Int = 1) -> String {
    if article == nil {
      return (!format.contains(.capitalized) || singular.first!.isUppercase)
      ? singular : singular.capitalized()
    } else if format.contains(.plural) || count > 1 {
      if format.contains(.noQuantity) || count == 1 {
        return format.contains(.capitalized) ? plural.capitalized() : plural
      } else {
        return "\(count) \(plural)"
      }
    } else {
      var out: String
      switch format.article {
      case .none: out = singular
      case .indefinite: out = "\(article!) \(singular)"
      case .definite: out = "the \(singular)"
      }
      return format.contains(.capitalized) ? out.capitalized() : out
    }
  }
}

extension NounPhrase: ValueConstructible {
  static func fromValue(_ value: Value) -> NounPhrase? {
    guard case let .string(s) = value else {
      return nil
    }
    return NounPhrase(s)
  }
}
