//
//  Matchable.swift
//  Wyrm
//

enum MatchQuality: Comparable {
  case none, partial, exact
}

enum MatchQuantity {
  case all
  case number(Int)
  case unspecified
}

protocol Matchable {
  func match(_ tokens: ArraySlice<String>) -> MatchQuality
}

extension String: Matchable {
  func match(_ tokens: ArraySlice<String>) -> MatchQuality {
    guard !tokens.isEmpty else {
      return .none
    }

    var tokens = tokens
    var quality = MatchQuality.exact
    for selfToken in TokenSequence(self) {
      guard let token = tokens.first else {
        break
      }
      let selfToken = selfToken.lowercased()
      if selfToken == token {
        quality = min(quality, .exact)
        tokens.removeFirst()
      } else if selfToken.hasPrefix(token) {
        quality = .partial
        tokens.removeFirst()
      } else {
        quality = .partial
      }
    }

    return tokens.isEmpty ? quality : .none
  }
}

extension NounPhrase: Matchable {
  func match(_ tokens: ArraySlice<String>) -> MatchQuality {
    let q = singular.match(tokens)
    return q == .exact ? q : max(q, plural.match(tokens))
  }
}

private func consumeQuantity(_ tokens: inout ArraySlice<String>) -> MatchQuantity {
  if tokens.first == "all" || tokens.first == "every" {
    tokens.removeFirst()
    return .all
  } else if tokens.first == "a" || tokens.first == "an" {
    tokens.removeFirst()
    return .number(1)
  } else if tokens.first == "the" {
    tokens.removeFirst()
    return .unspecified
  } else if let n = Int(tokens.first!) {
    tokens.removeFirst()
    return .number(n)
  } else {
    return .unspecified
  }
}

struct MatchResult<T> {
  let quality: MatchQuality
  let quantity: MatchQuantity
  let matches: [T]
}

extension MatchResult: Collection {
  var startIndex: Int { matches.startIndex }
  var endIndex: Int { matches.endIndex }
  subscript(position: Int) -> T { matches[position] }
  func index(after i: Int) -> Int { i + 1 }
}

func match<T: Matchable>(_ tokens: [String], against subjectLists: any Sequence<T>...) -> MatchResult<T>? {
  var tokens = tokens[...]

  let matchQuantity = consumeQuantity(&tokens)
  var matchQuality = MatchQuality.partial
  var matches = [T]()

  for subjects in subjectLists {
    for subject in subjects {
      let quality = subject.match(tokens)
      if quality > matchQuality {
        matches = [subject]
        matchQuality = quality
      } else if quality == matchQuality {
        matches.append(subject)
      }
    }
  }

  return matches.isEmpty ? nil : MatchResult(quality: matchQuality, quantity: matchQuantity,
                                             matches: matches)
}

func match<T: Matchable>(_ tokens: [String], against subjectLists: any Sequence<T>...,
                         where pred: (T) -> Bool) -> MatchResult<T>? {
  return match(tokens, against: subjectLists.flatMap({ $0.filter(pred) }))
}

func match<K, V: Matchable>(_ tokens: [String], againstValues subjectDict: [K:V]) -> MatchResult<K>? {
  var tokens = tokens[...]

  let matchQuantity = consumeQuantity(&tokens)
  var matchQuality = MatchQuality.partial
  var matches = [K]()

  for (key, subject) in subjectDict {
    let quality = subject.match(tokens)
    if quality > matchQuality {
      matches = [key]
      matchQuality = quality
    } else if quality == matchQuality {
      matches.append(key)
    }
  }

  return matches.isEmpty ? nil : MatchResult(quality: matchQuality, quantity: matchQuantity,
                                             matches: matches)
}
