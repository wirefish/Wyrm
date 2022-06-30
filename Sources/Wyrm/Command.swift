//
//  Command.swift
//  Wyrm
//
//  Created by Craig Becker on 6/29/22.
//

enum ClauseSpec {
    // The clause consumes a phrase starting with one of the words in preps and
    // continuing either until the first prep that begins a subsequent clause, or
    // the end of the input.
    case phrase([String], String)

    // The clause consumes one word, if a word is present.
    case word(String)

    // The clause consumes the rest of the input.
    case rest(String)
}

// The result of parsing a clause based on its grammar.
enum Clause {
    case phrase(String?, [String])
    case word(String)
    case rest(String)
}

struct TokenSequence: Sequence, IteratorProtocol {
    private var input: Substring

    init(_ input: String) {
        self.input = Substring(input)
    }

    func peek() -> Substring? {
        guard let start = input.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        let end = input[start...].firstIndex(where: { $0.isWhitespace }) ?? input.endIndex
        return input[start..<end]
    }

    @discardableResult
    mutating func consume() -> Bool {
        next() != nil
    }

    mutating func next() -> Substring? {
        guard let start = input.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        input.removeSubrange(..<start)
        let end = input.firstIndex(where: { $0.isWhitespace }) ?? input.endIndex
        let token = input[..<end]
        input.removeSubrange(..<end)
        return token
    }

    mutating func rest() -> Substring? {
        guard let start = input.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        let rest = input[start...]
        input.removeAll()
        return rest
    }
}

struct Grammar {
    let verbs: [String]
    let clauses: [ClauseSpec]

    init?(_ s: String) {
        var it = TokenSequence(s).makeIterator()

        guard let verbs = it.next() else {
            logger.error("command grammar is empty")
            return nil
        }
        self.verbs = verbs.split(separator: "|").map { String($0) }

        var clauses = [ClauseSpec]()
        while let clause = it.next() {
            let parts = clause.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                logger.error("malformed clause specification \(clause)")
                return nil
            }
            let preps = parts[0].split(separator: "|").map{ String($0) }
            let name = String(parts[1])
            clauses.append(.phrase(preps, name))
        }
        self.clauses = clauses
    }
}

class Command {
    typealias RunFunction = (Avatar, String, [Clause?]) -> Void

    let grammar: Grammar
    let fn: RunFunction
    let allPreps: [String:Int]

    init(_ grammarSpec: String, _ fn: @escaping RunFunction) {
        self.grammar = Grammar(grammarSpec)!
        self.fn = fn

        allPreps = [String:Int](uniqueKeysWithValues: grammar.clauses.enumerated().flatMap {
            (index, spec) -> [(String, Int)] in
            guard case let .phrase(preps, _) = spec else {
                return []
            }
            return preps.map { ($0, index) }
        })
    }

    func run(_ actor: Avatar, _ verb: String, _ rest: inout TokenSequence) {
        fn(actor, verb, parseClauses(&rest))
    }

    func parseClauses(_ tokens: inout TokenSequence) -> [Clause?] {
        var clauses = [Clause?]()
        var needsPrep = false

        // Each iteration of this loop attempts to match the remaining input against
        // the next clause in the grammar.
        for spec in grammar.clauses {
            switch spec {
            case .word:
                if let word = tokens.next() {
                    clauses.append(.word(word.lowercased()))
                } else {
                    clauses.append(nil)
                }

            case .rest:
                if let rest = tokens.rest() {
                    clauses.append(.rest(String(rest)))  // FIXME: normalize whitespace
                } else {
                    clauses.append(nil)
                }

            case let .phrase(preps, _):
                // If the input begins with a prep associated with this clause *or*
                // this is the first prepositional clause, find the position of the
                // first word that is a prep associated with any later clause. This
                // clause matches the text until that position.
                var prep = tokens.peek()?.lowercased()
                if prep == nil {
                    clauses.append(nil)
                    break
                }
                var found = false
                if preps.contains(prep!) {
                    tokens.consume()
                    found = true
                } else if !needsPrep {
                    prep = nil
                    found = true
                }
                if found {
                    var phraseTokens = [String]()
                    while let token = tokens.peek()?.lowercased() {
                        guard allPreps[token] == nil else {
                            break
                        }
                        phraseTokens.append(token)
                        tokens.consume()
                    }
                    clauses.append(phraseTokens.isEmpty ? nil : .phrase(prep, phraseTokens))
                }
                needsPrep = true
            }
        }

        return clauses
    }

    static let allCommands = [
        lookCommand,
    ]

    static let verbsToCommands = [String:Command](
        uniqueKeysWithValues: allCommands.flatMap { command in
            command.grammar.verbs.map { ($0, command) }
        })

    static func processInput(actor: Avatar, input: String) -> String? {
        guard input.count <= 1000 else {
            // Silently ignore large input.
            return nil
        }

        var tokens = TokenSequence(input)
        guard let verb = tokens.next()?.lowercased() else {
            // Silently ignore empty input.
            return nil
        }

        guard let command = verbsToCommands[verb] else {
            return "Invalid command \"\(verb)\"."
        }

        command.run(actor, verb, &tokens)
        return nil
    }
}

// TEST:
let lookCommand = Command("look at:target with|using|through:tool") {
    actor, verb, clauses in
    print(clauses)
    guard let location = actor.location else {
        return
    }
}

