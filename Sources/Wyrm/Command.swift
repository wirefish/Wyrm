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

    mutating func rest() -> String? {
        return peek() != nil ? joined(separator: " ") : nil
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
        var hasPhraseClause = false
        while let clause = it.next() {
            let parts = clause.split(separator: ":", maxSplits: 1)
            switch parts.count {
            case 1:
                if !hasPhraseClause {
                    clauses.append(.phrase([], String(parts[0])))
                    hasPhraseClause = true
                } else {
                    logger.error("phrase clauses after the first must specify at least one preposition")
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
    enum Clause {
        case empty
        case tokens([String])
        case string(String)

        var asString: String {
            switch self {
            case .empty: return ""
            case let .tokens(tokens): return tokens.joined(separator: " ")
            case let .string(s): return s
            }
        }
    }

    typealias RunFunction = (Avatar, String, [Clause]) -> Void

    let grammar: Grammar
    let aliases: [(String,String)]
    let help: String?
    let fn: RunFunction
    let allPreps: [String:Int]

    init(_ grammarSpec: String, aliases: [[String]:String] = [:], help: String? = nil,
         _ fn: @escaping RunFunction) {
        self.grammar = Grammar(grammarSpec)!
        self.aliases = aliases.flatMap { keys, value in keys.map { ($0, value) } }
        self.help = help
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

    private func parseClauses(_ tokens: inout TokenSequence) -> [Clause] {
        var clauses = [Clause]()
        var needsPrep = false

        // Each iteration of this loop attempts to match the remaining input against
        // the next clause in the grammar.
        for clause in grammar.clauses {
            switch clause {
            case .word:
                if let word = tokens.next() {
                    clauses.append(.string(word.lowercased()))
                } else {
                    clauses.append(.empty)
                }

            case .rest:
                if let rest = tokens.rest() {
                    clauses.append(.string(rest))
                } else {
                    clauses.append(.empty)
                }

            case let .phrase(preps, _):
                // If the input begins with a prep associated with this clause *or*
                // this is the first prepositional clause, find the position of the
                // first word that is a prep associated with any later clause. This
                // clause matches the text until that position.
                var prep = tokens.peek()?.lowercased()
                if prep == nil {
                    clauses.append(.empty)
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
                    clauses.append(phraseTokens.isEmpty ? .empty : .tokens(phraseTokens))
                }
                needsPrep = true
            }
        }

        return clauses
    }
}

// MARK: - processing input

extension Command {
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

    static func matchVerb(_ verb: String) -> ArraySlice<VerbAction> {
        guard let index = verbActions.lowerBound(for: VerbAction(verb: verb, action: .none)),
              verbActions[index].verb.hasPrefix(verb) else {
            return []
        }

        if verbActions[index].verb == verb {
            return verbActions[index...index]
        }

        let end = verbActions[index...].firstIndex(where: { !$0.verb.hasPrefix(verb) }) ?? verbActions.endIndex
        return verbActions[index..<end]
    }

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

        let actions = matchVerb(verb)
        if actions.isEmpty {
            actor.show("Unknown command \"\(verb)\".")
            return
        }

        if actions.count > 1 {
            let alts = actions.map(\.verb).conjunction(using: "or")
            actor.show("Ambiguous command \"\(verb)\". Did you mean \(alts)?")
            return
        }

        switch actions.first!.action {
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

// MARK: - help command

let helpIntro = """
Help is available on the following topics. Type `help` followed by the topic of
interest for more information.
"""

func primaryCommandVerbs() -> [String] {
    allCommands.map({ $0.grammar.verbs.first! }).sorted()
}

let helpCommand = Command("help 1:topic 1:subtopic") { actor, verb, clauses in
    if case let .string(topic) = clauses[0] {
        let actions = Command.matchVerb(topic)
        if actions.isEmpty {
            actor.show("There is no help available for that topic.")
        } else if actions.count > 1 {
            actor.show("Did you mean \(actions.map({ "`help:\($0.verb)`" }).conjunction(using: "or"))?")
        } else {
            switch actions.first!.action {
            case let .alias(alias):
                actor.show("The command `\(actions.first!.verb)` is an alias for `\(alias)`.")
                Command.processInput(actor: actor, input: "help \(alias)")
            case let .command(command):
                if let help = command.help {
                    actor.show(help)
                } else {
                    actor.show("There is no help available for that command.")
                }
            case .none:
                // This should never happen as .none is only used for searching.
                break
            }
        }
    } else {
        let verbs = primaryCommandVerbs()
        actor.showLinks(helpIntro, "help", verbs)
    }
}

// MARK: - registry of all commands

// NOTE: To make a command available, add it to this array!
let allCommands = [
    acceptCommand,
    declineCommand,
    equipCommand,
    goCommand,
    helpCommand,
    inventoryCommand,
    lookCommand,
    meditateCommand,
    questCommand,
    sayCommand,
    takeCommand,
    talkCommand,
    tutorialCommand,
    unequipCommand,
]
