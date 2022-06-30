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
    var brief: NounPhrase? { get }
    var alts: [NounPhrase] { get }
}

extension String {
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

extension NounPhrase {
    func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        let q = singular.match(tokens)
        return q == .exact ? q : max(q, plural.match(tokens))
    }
}

extension Matchable {
    func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return alts.reduce(brief?.match(tokens) ?? .none) { max($0, $1.match(tokens)) }
    }
}

func consumeQuantity(_ tokens: inout ArraySlice<String>) -> MatchQuantity {
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

func match(_ tokens: [String], against subject: Entity) -> (MatchQuality, MatchQuantity) {
    var tokens = tokens[...]
    let matchQuantity = consumeQuantity(&tokens)
    return ((subject as? Matchable)?.match(tokens) ?? .none, matchQuantity)
}

func match(_ tokens: [String], against subjects: [Entity]) -> (MatchQuality, MatchQuantity, [Entity])? {
    var tokens = tokens[...]

    let matchQuantity = consumeQuantity(&tokens)
    var matchEntities = [Entity]()
    var matchQuality = MatchQuality.partial

    for subject in subjects {
        guard let matchable = subject as? Matchable else {
            continue
        }
        let quality = matchable.match(tokens)
        if quality > matchQuality {
            matchEntities = [subject]
            matchQuality = quality
        } else if quality == matchQuality {
            matchEntities.append(subject)
        }
    }

    return matchEntities.isEmpty ? nil : (matchQuality, matchQuantity, matchEntities)
}
