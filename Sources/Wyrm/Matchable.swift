//
//  Matchable.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum MatchQuality: Comparable {
    case none, partial, exact
}

enum MatchQuantity {
    case all
    case number(Int)
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
    } else if tokens.first == "a" || tokens.first == "an" || tokens.first == "the" {
        // FIXME: for "the" it should really depend on if the better match is against
        // the singular or plural form...
        tokens.removeFirst()
        return .number(1)
    } else if let n = Int(tokens.first!) {
        tokens.removeFirst()
        return .number(n)
    } else {
        return .all
    }
}

struct MatchResult<T: Matchable> {
    let quality: MatchQuality
    let quantity: MatchQuantity
    let matches: [T]
}

func match<T: Matchable>(_ tokens: [String], against subjects: [T]) -> MatchResult<T>? {
    var tokens = tokens[...]

    let matchQuantity = consumeQuantity(&tokens)
    var matchQuality = MatchQuality.partial
    var matches = [T]()

    for subject in subjects {
        let quality = subject.match(tokens)
        if quality > matchQuality {
            matches = [subject]
            matchQuality = quality
        } else if quality == matchQuality {
            matches.append(subject)
        }
    }

    return matches.isEmpty ? nil : MatchResult(quality: matchQuality, quantity: matchQuantity, matches: matches)
}

func match<T: Matchable>(_ tokens: [String], against subjects: [T], where pred: (T) -> Bool) -> MatchResult<T>? {
    return match(tokens, against: subjects.filter(pred))
}
