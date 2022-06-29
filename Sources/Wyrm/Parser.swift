//
//  Parser.swift
//  Wyrm
//
//  Created by Craig Becker on 6/23/22.
//

struct Parameter {
    static let selfConstraint = ValueRef.relative("self")

    let name: String
    let constraint: ValueRef?
}

indirect enum ParseNode {
    typealias Member = (name: String, initialValue: ParseNode)
    typealias Handler = (EventPhase, String, [Parameter], ParseNode)

    // Literal values.
    case boolean(Bool)
    case number(Double)
    case string(String)
    case symbol(String)

    // Expressions.
    case identifier(String)
    case unaryExpr(Token, ParseNode)
    case binaryExpr(ParseNode, Token, ParseNode)
    case conjuction(ParseNode, ParseNode)
    case disjunction(ParseNode, ParseNode)
    case list([ParseNode])
    case call(ParseNode, [ParseNode])
    case dot(ParseNode, String)
    case `subscript`(ParseNode, ParseNode)
    case exit(ParseNode, Direction, ParseNode)

    // Statements.
    case `var`(String, ParseNode)
    case `if`(ParseNode, ParseNode, ParseNode?)
    case `for`(String, ParseNode, ParseNode)
    case await(ParseNode)
    case `return`(ParseNode)
    case block([ParseNode])
    case assignment(ParseNode, Token, ParseNode)
    case ignoredValue(ParseNode)

    // Top-level definitions.
    case entity(name: String, prototype: ValueRef, members: [Member],
                handlers: [Handler], startable: Bool)
    case quest(name: String, members: [Member], handlers: [Handler])

    // True if this node can syntactically be on the left side of an assignment.
    var isAssignable: Bool {
        switch self {
        case .identifier(_): return true
        case .dot(_, _): return true
        case .subscript(_, _): return true
        default: return false
        }
    }
}

enum Precedence: Int, Comparable {
    case none = 0
    case assign
    case or
    case and
    case equality
    case comparison
    case term
    case factor
    case unary
    case call

    static func < (lhs: Precedence, rhs: Precedence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func nextHigher() -> Precedence {
        return Precedence(rawValue: rawValue + 1)!
    }
}

typealias InfixParserMethod = (Parser) -> (_ lhs: ParseNode) -> ParseNode?
typealias ParseRule = (method: InfixParserMethod, prec: Precedence)

class Parser {
    static let parseRules: [Token:ParseRule] = [
        .lparen: (method: parseCall, prec: .call),
        .lsquare: (method: parseSubscript, prec: .call),
        .leads: (method: parseExit, prec: .factor),
        .dot: (method: parseDot, prec: .call),
        .minus: (method: parseBinary, prec: .term),
        .minusEqual: (method: parseAssignment, prec: .assign),
        .plus: (method: parseBinary, prec: .term),
        .plusEqual: (method: parseAssignment, prec: .assign),
        .slash: (method: parseBinary, prec: .factor),
        .slashEqual: (method: parseAssignment, prec: .assign),
        .star: (method: parseBinary, prec: .factor),
        .starEqual: (method: parseAssignment, prec: .assign),
        .percent: (method: parseBinary, prec: .factor),
        .percentEqual: (method: parseAssignment, prec: .assign),
        .notEqual: (method: parseBinary, prec: .equality),
        .equal: (method: parseAssignment, prec: .assign),
        .equalEqual: (method: parseBinary, prec: .equality),
        .less: (method: parseBinary, prec: .comparison),
        .lessEqual: (method: parseBinary, prec: .comparison),
        .greater: (method: parseBinary, prec: .comparison),
        .greaterEqual: (method: parseBinary, prec: .comparison),
        .and: (method: parseAnd, prec: .and),
        .or: (method: parseOr, prec: .or),
    ]

    let scanner: Scanner
    var currentToken: Token = .endOfInput

    init(scanner: Scanner) {
        self.scanner = scanner
    }

    func parse() -> [ParseNode] {
        advance()

        var defs = [ParseNode]()
        while currentToken != .endOfInput {
            if let def = parseDefinition() {
                defs.append(def)
            }
        }
        return defs
    }
    
    private func parseDefinition() -> ParseNode? {
        switch currentToken {
        case .def, .deflocation:
            return parseEntity()
        case .defquest:
            return parseQuest()
        default:
            error("invalid token \(currentToken) at top level")
            advance()
            return nil
        }
    }

    // MARK: - parsing observers

    private func parseObserverBody(_ type: String) -> ([ParseNode.Member], [ParseNode.Handler]) {
        guard case .lbrace = consume() else {
            error("expected { at start of \(type) body")
            return ([], [])
        }

        var members = [ParseNode.Member]()
        var handlers = [ParseNode.Handler]()
        loop: while true {
            switch currentToken {
            case .endOfInput:
                error("unterminated \(type) body")
                break loop
            case .rbrace:
                advance()
                break loop
            case .identifier:
                if let member = parseMember() {
                    members.append(member)
                }
            case .allow, .before, .when, .after:
                if let handler = parseHandler() {
                    handlers.append(handler)
                }
            default:
                error("invalid token \(currentToken) at top level within \(type) body")
                advance()
                break
            }
        }

        return (members, handlers)
    }

    private func parseMember() -> ParseNode.Member? {
        guard case let .identifier(name) = consume() else {
            fatalError("invalid call to parseMember")
        }

        guard case .equal = consume() else {
            error("expected = after member name")
            return nil
        }

        if let initializer = parseExpr() {
            return (name, initializer)
        } else {
            return nil
        }
    }

    private func parseHandler() -> ParseNode.Handler? {
        var phase: EventPhase
        switch consume() {
        case .allow: phase = .allow
        case .before: phase = .before
        case .when: phase = .when
        case .after: phase = .after
        default: fatalError("invalid event phase")
        }

        guard case let .identifier(event) = consume() else {
            error("expected event name after \(phase)")
            return nil
        }

        guard case .lparen = consume() else {
            error("expected ( after event handler name")
            return nil
        }

        var params = [Parameter]()
        while !match(.rparen) {
            guard case var .identifier(name) = consume() else {
                error("parameter name must be an identifier")
                return nil
            }

            guard var constraint = parsePrototype() else {
                return nil
            }

            // As a special case, a parameter named self is just an anonymous parameter with
            // a self constraint.
            if name == "self" {
                if constraint == nil {
                    constraint = Parameter.selfConstraint
                    name = "$\(params.count + 1)"
                } else {
                    error("parameter named self cannot have a constraint")
                }
            }

            params.append(Parameter(name: name, constraint: constraint))

            if currentToken != .rparen && !match(.comma) {
                error("expected , between function parameters")
            }
        }

        if let block = parseBlock() {
            return (phase, event, params, block)
        } else {
            return nil
        }
    }

    // MARK: - parsing entities

    private func parseEntity() -> ParseNode? {
        let def = consume()

        guard case let .identifier(name) = consume() else {
            error("expected identifier after \(def)")
            return nil
        }

        guard case let prototype?? = parsePrototype() else {
            error("prototype required for entity definition")
            return nil
        }

        let (members, handlers) = parseObserverBody("entity")

        let startable = def == .deflocation
        return .entity(name: name, prototype: prototype, members: members,
                       handlers: handlers, startable: startable)
    }

    private func parsePrototype() -> ValueRef?? {
        if !match(.colon) {
            return .some(nil)
        }

        guard case let .identifier(prefix) = consume() else {
            error("expected identifier")
            return nil
        }

        if match(.dot) {
            guard case let .identifier(name) = consume() else {
                error("expected identifier")
                return nil
            }
            return .absolute(prefix, name)
        } else {
            return .relative(prefix)
        }
    }

    private func parseQuest() -> ParseNode? {
        let _ = consume()

        guard case let .identifier(name) = consume() else {
            error("expected identifier after defquest")
            return nil
        }

        let (members, handlers) = parseObserverBody("entity")

        return .quest(name: name, members: members, handlers: handlers)
    }

    // MARK: - parsing statements

    private func parseStatement() -> ParseNode? {
        switch currentToken {
        case .var:
            return parseVar()
        case .if:
            return parseIf()
        case .for:
            return parseFor()
        case .await:
            return parseAwait()
        case .return:
            return parseReturn()
        default:
            guard let expr = parseExpr(.assign) else {
                return nil
            }
            if case .assignment = expr {
                return expr
            } else {
                return .ignoredValue(expr)
            }
        }
    }

    private func parseVar() -> ParseNode? {
        assert(match(.var))

        guard case let .identifier(name) = consume() else {
            error("expected variable name")
            return nil
        }

        guard case .equal = consume() else {
            error("expected = after variable name")
            return nil
        }

        guard let value = parseExpr() else {
            return nil
        }

        return .var(name, value)
    }

    private func parseIf() -> ParseNode? {
        assert(match(.if))

        guard let predicate = parseExpr() else {
            return nil
        }

        guard let whenTrue = parseBlock() else {
            return nil
        }

        var whenFalse: ParseNode?
        if match(.else) {
            whenFalse = currentToken == .if ? parseIf() : parseBlock()
        }

        return .if(predicate, whenTrue, whenFalse)
    }

    private func parseFor() -> ParseNode? {
        assert(match(.for))

        guard case let .identifier(variable) = consume() else {
            error("invalid loop variable")
            return nil
        }

        guard case .in = consume() else {
            error("expected 'in' after loop variable name")
            return nil
        }

        guard let sequence = parseExpr() else {
            return nil
        }

        guard let body = parseBlock() else {
            return nil
        }

        return .for(variable, sequence, body)
    }

    private func parseBlock() -> ParseNode? {
        guard case .lbrace = consume() else {
            error("expected { at beginning of block")
            return nil
        }

        var stmts = [ParseNode]()
        while !match(.rbrace) {
            if let stmt = parseStatement() {
                stmts.append(stmt)
            } else {
                return nil
            }
        }

        return .block(stmts)
    }

    private func parseAwait() -> ParseNode? {
        assert(match(.await))
        guard let rhs = parseExpr() else {
            return nil
        }
        return .await(rhs)
    }

    private func parseReturn() -> ParseNode? {
        assert(match(.return))
        guard let rhs = parseExpr() else {
            return nil
        }
        return .return(rhs)
    }

    private func parseAssignment(lhs: ParseNode) -> ParseNode? {
        let op = consume()
        guard let rhs = parseExpr(Parser.parseRules[op]!.prec.nextHigher()) else {
            return nil
        }
        if !lhs.isAssignable {
            error("operand before \(op) is not assignable")
            return nil
        }
        return .assignment(lhs, op, rhs)
    }

    // MARK: - parsing expressions

    private func parseExpr(_ prec: Precedence = .or) -> ParseNode? {
        var node: ParseNode?
        switch currentToken {
        case let .boolean(b):
            node = .boolean(b)
            advance()
        case let .number(n):
            node = .number(n)
            advance()
        case let .string(s):
            node = .string(s)
            advance()
        case let .symbol(s):
            node = .symbol(s)
            advance()
        case let .identifier(s):
            node = .identifier(s)
            advance()
        case .minus, .not:
            node = parseUnary()
        case .lparen:
            node = parseGroup()
        case .lsquare:
            node = parseList()
        default:
            error("expected expression at \(currentToken)")
            advance()
            return nil
        }

        while let rule = Parser.parseRules[currentToken], node != nil {
            if prec <= rule.prec {
                node = rule.method(self)(node!)
            } else {
                break
            }
        }

        if currentToken.isAssignment {
            error("invalid assignment")
            advance()
            return nil
        }

        return node
    }

    private func parseUnary() -> ParseNode? {
        let op = consume()
        if let rhs = parseExpr(.unary) {
            return .unaryExpr(op, rhs)
        } else {
            return nil
        }
    }

    private func parseGroup() -> ParseNode? {
        assert(match(.lparen))
        if let expr = parseExpr() {
            if match(.rparen) {
                return expr
            } else {
                error("expected ) after expression")
            }
        }
        return nil
    }

    private func parseList() -> ParseNode? {
        assert(match(.lsquare))

        var elements = [ParseNode]()
        while !match(.rsquare) {
            if let expr = parseExpr() {
                elements.append(expr)
            }
            if currentToken != .rsquare && !match(.comma) {
                error("expected , between list elements")
            }
        }

        return .list(elements)
    }

    private func parseBinary(lhs: ParseNode) -> ParseNode? {
        let op = consume()
        if let rhs = parseExpr(Parser.parseRules[op]!.prec.nextHigher()) {
            return .binaryExpr(lhs, op, rhs)
        } else {
            return nil
        }
    }

    private func parseAnd(lhs: ParseNode) -> ParseNode? {
        advance()
        if let rhs = parseExpr(.and.nextHigher()) {
            return .conjuction(lhs, rhs)
        } else {
            return nil
        }
    }

    private func parseOr(lhs: ParseNode) -> ParseNode? {
        advance()
        if let rhs = parseExpr(.or.nextHigher()) {
            return .disjunction(lhs, rhs)
        } else {
            return nil
        }
    }

    private func parseCall(lhs: ParseNode) -> ParseNode? {
        assert(match(.lparen))
        var args = [ParseNode]()
        while !match(.rparen) {
            if let arg = parseExpr() {
                args.append(arg)
            }
            if currentToken != .rparen && !match(.comma) {
                error("expected , between function arguments")
            }
        }

        // Allow for a trailing string/text literal as the final argument.
        if case let .string(s) = currentToken {
            args.append(.string(s))
            advance()
        }

        return .call(lhs, args)
    }

    private func parseSubscript(lhs: ParseNode) -> ParseNode? {
        assert(match(.lsquare))

        guard let expr = parseExpr() else {
            return nil
        }

        guard case .rsquare = consume() else {
            error("expected ] after subscript expression")
            return nil
        }

        return .subscript(lhs, expr)
    }

    private func parseDot(lhs: ParseNode) -> ParseNode? {
        assert(match(.dot))

        guard case let .identifier(name) = consume() else {
            error("expected identifier after .")
            return nil
        }

        return .dot(lhs, name)
    }

    private func parseExit(lhs: ParseNode) -> ParseNode? {
        assert(match(.leads))

        guard case let .symbol(name) = consume() else {
            error("expected symbol after ->")
            return nil
        }

        guard let dir = Direction(fromValue: .symbol(name)) else {
            error("invalid direction \(name) after ->")
            return nil
        }

        let _ = match(.oneway)  // FIXME:

        if !match(.to) {
            error("expected 'to' after exit direction")
            return nil
        }

        guard let rhs = parseExpr() else {
            return nil
        }

        return .exit(lhs, dir, rhs)
    }

    // MARK: - consuming tokens

    private func advance() {
        while true {
            currentToken = scanner.nextToken()
            if case let .error(line, message) = currentToken {
                print("\(line): syntax error: \(message)")
            } else {
                break
            }
        }
    }

    private func consume() -> Token {
        let token = currentToken
        advance()
        return token
    }

    private func match(_ token: Token) -> Bool {
        if currentToken == token {
            advance()
            return true
        } else {
            return false
        }
    }

    // MARK: - generating error messages

    private func error(_ message: String) {
        print("\(scanner.currentLine): \(message)")
    }
}
