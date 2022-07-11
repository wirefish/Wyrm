//
//  Command.swift
//  Wyrm
//

// MARK: - TokenSequence

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

// MARK: - Grammar

struct Grammar {
    enum Clause {
        // The clause consumes a phrase starting with one of the words in preps and
        // continuing either until the first prep that begins a subsequent clause, or
        // the end of the input.
        case phrase([String], String)

        // The clause consumes one word, if a word is present.
        case word(String)

        // The clause consumes the rest of the input.
        case rest(String)
    }

    let verbs: [String]
    let clauses: [Clause]

    init?(_ s: String) {
        var it = TokenSequence(s).makeIterator()

        guard let verbs = it.next() else {
            logger.error("command grammar is empty")
            return nil
        }
        self.verbs = verbs.split(separator: "|").map { String($0) }

        var clauses = [Clause]()
        while let clause = it.next() {
            let parts = clause.split(separator: ":", maxSplits: 1)
            switch parts.count {
            case 1:
                if clauses.isEmpty {
                    clauses.append(.phrase([], String(parts[0])))
                } else {
                    logger.error("clauses after the first must specify at least one preposition")
                }
            case 2:
                let name = String(parts[1])
                switch parts[0] {
                case "1":
                    clauses.append(.word(name))
                case "*":
                    clauses.append(.rest(name))
                default:
                    let preps = parts[0].split(separator: "|").map{ String($0) }
                    clauses.append(.phrase(preps, name))
                }
            default:
                logger.error("malformed clause specification \(clause)")
                return nil
            }
        }
        self.clauses = clauses
    }
}

// MARK: - Command

class Command {
    typealias Clause = [String]
    typealias RunFunction = (Avatar, String, [Clause?]) -> Void

    let grammar: Grammar
    let aliases: [(String,String)]
    let fn: RunFunction
    let allPreps: [String:Int]

    init(_ grammarSpec: String, aliases: [[String]:String] = [:], _ fn: @escaping RunFunction) {
        self.grammar = Grammar(grammarSpec)!
        self.aliases = aliases.flatMap { keys, value in keys.map { ($0, value) } }
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
        for clause in grammar.clauses {
            switch clause {
            case .word:
                if let word = tokens.next() {
                    clauses.append([word.lowercased()])
                } else {
                    clauses.append(nil)
                }

            case .rest:
                if let rest = tokens.rest() {
                    clauses.append([String(rest)])
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
                    clauses.append(phraseTokens.isEmpty ? nil : phraseTokens)
                }
                needsPrep = true
            }
        }

        return clauses
    }

    struct VerbAction: Comparable {
        enum Action {
            case none
            case command(Command)
            case alias(String)
        }
        let verb: String
        let action: Action

        static func == (_ lhs: VerbAction, _ rhs: VerbAction) -> Bool {
            return lhs.verb == rhs.verb
        }

        static func < (_ lhs: VerbAction, _ rhs: VerbAction) -> Bool {
            return lhs.verb < rhs.verb
        }
    }

    static let verbActions = allCommands.flatMap { command in
        command.grammar.verbs.map { VerbAction(verb: $0, action: .command(command)) } +
        command.aliases.map { VerbAction(verb: $0, action: .alias($1)) }
    }.sorted()

    static func processInput(actor: Avatar, input: String) {
        guard input.count <= 1000 else {
            // Silently ignore large input.
            return
        }

        var tokens = TokenSequence(input)
        guard let verb = tokens.next()?.lowercased() else {
            // Silently ignore empty input.
            return
        }

        guard let index = verbActions.lowerBound(for: VerbAction(verb: verb, action: .none)),
              verbActions[index].verb.hasPrefix(verb) else {
            actor.show("Unknown command \"\(verb)\".")
            return
        }

        if (verbActions[index].verb != verb) {
            let end = verbActions[index...].firstIndex(where: {
                !$0.verb.hasPrefix(verb)
            }) ?? verbActions.endIndex
            if end != index.advanced(by: 1) {
                let alts = verbActions[index..<end].map(\.verb).conjunction(using: "or")
                actor.show("Ambiguous command \"\(verb)\". Did you mean \(alts)?")
                return
            }
        }

        switch verbActions[index].action {
        case .none:
            break
        case let .command(command):
            command.run(actor, verb, &tokens)
        case let .alias(alias):
            // FIXME: retain rest of input and append it to alias?
            processInput(actor: actor, input: alias)
        }
    }
}

// MARK: - allCommands

// NOTE: To make a command available, add it to this array!
let allCommands = [
    goCommand,
    lookCommand,
]
