//
//  Parser.swift
//  Wyrm
//
//  Created by Craig Becker on 6/23/22.
//

import Foundation

struct Parameter {
    let name: String
    let constraint: [String]
}

indirect enum ParseNode {
    case literal(Token)
    case identifier(String)
    case unaryExpr(Token, ParseNode)
    case binaryExpr(ParseNode, Token, ParseNode)
    case list([ParseNode])
    case call(ParseNode, [ParseNode])
    case dot(ParseNode, String)
    case `subscript`(ParseNode, ParseNode)
    case `var`(String, ParseNode)
    case `if`(ParseNode, ParseNode, ParseNode?)
    case `for`(String, ParseNode, ParseNode)
    case block([ParseNode])
    case initializer([String], ParseNode)
    case handler(String, [Parameter], ParseNode)
    case member(name: String, value: ParseNode)
    case exit(ParseNode, Direction, ParseNode)
    case entity(name: String, prototype: [String], members: [ParseNode],
                initializer: ParseNode?, handlers: [ParseNode])
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

typealias BinaryParserMethod = (Parser) -> (_ lhs: ParseNode) -> ParseNode?
typealias ParseRule = (method: BinaryParserMethod?, prec: Precedence)

class Parser {
    static let parseRules: [Token:ParseRule] = [
        .lparen: (method: parseCall, prec: .call),
        .lsquare: (method: parseSubscript, prec: .call),
        .leads: (method: parseExit, prec: .assign),
        .dot: (method: parseDot, prec: .call),
        .minus: (method: parseBinary, prec: .term),
        .minusEqual: (method: parseBinary, prec: .assign),
        .plus: (method: parseBinary, prec: .term),
        .plusEqual: (method: parseBinary, prec: .assign),
        .slash: (method: parseBinary, prec: .factor),
        .slashEqual: (method: parseBinary, prec: .assign),
        .star: (method: parseBinary, prec: .factor),
        .starEqual: (method: parseBinary, prec: .assign),
        .percent: (method: parseBinary, prec: .factor),
        .percentEqual: (method: parseBinary, prec: .assign),
        .notEqual: (method: parseBinary, prec: .equality),
        .equal: (method: parseBinary, prec: .assign),
        .equalEqual: (method: parseBinary, prec: .equality),
        .less: (method: parseBinary, prec: .comparison),
        .lessEqual: (method: parseBinary, prec: .comparison),
        .greater: (method: parseBinary, prec: .comparison),
        .greaterEqual: (method: parseBinary, prec: .comparison),
        .and: (method: parseBinary, prec: .and),
        .or: (method: parseBinary, prec: .or),
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

    // MARK: - parsing definitions
    
    private func parseDefinition() -> ParseNode? {
        switch currentToken {
        case .def, .deflocation:
            return parseEntity()
        default:
            print("invalid token \(currentToken) at top level")
            advance()
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

        guard let prototype = parsePrototype() else {
            return nil
        }

        guard case .lbrace = consume() else {
            error("expected { at start of entity body")
            return nil
        }

        var members = [ParseNode]()
        var initializer: ParseNode?
        var handlers = [ParseNode]()
        loop: while true {
            switch currentToken {
            case .endOfInput:
                error("unterminated entity body")
                break loop
            case .rbrace:
                advance()
                break loop
            case .identifier:
                if let member = parseMember() {
                    members.append(member)
                }
            case .initializer:
                initializer = parseInitializer()
            case .allow, .before, .after:
                if let handler = parseHandler() {
                    handlers.append(handler)
                }
            default:
                error("invalid token \(currentToken) at top level within entity body")
                advance()
                break
            }
        }

        return .entity(name: name, prototype: prototype, members: members,
                       initializer: initializer, handlers: handlers)
    }

    private func parsePrototype() -> [String]? {
        if !match(.colon) {
            return []
        }

        var prototype = [String]()
        guard case let .identifier(name) = consume() else {
            error("expected identifier")
            return nil
        }
        prototype.append(name)

        while match(.dot) {
            guard case let .identifier(name) = consume() else {
                error("expected identifier")
                return nil
            }
            prototype.append(name)
        }

        return prototype
    }

    private func parseMember() -> ParseNode? {
        guard case let .identifier(name) = consume() else {
            fatalError("invalid call to parseMember")
        }

        guard case .equal = consume() else {
            error("expected = after member name")
            return nil
        }

        if let value = parseExpr() {
            return .member(name: name, value: value)
        } else {
            return nil
        }
    }

    private func parseInitializer() -> ParseNode? {
        advance()  // past init

        guard case .lparen = consume() else {
            error("expected ( after init")
            return nil
        }

        var params = [String]()
        while !match(.rparen) {
            guard case let .identifier(name) = consume() else {
                error("parameter name must be an identifier")
                return nil
            }
            params.append(name)

            if currentToken != .rparen && !match(.comma) {
                error("expected , between initializer parameters")
            }
        }

        if let block = parseBlock() {
            return .initializer(params, block)
        } else {
            return nil
        }
    }

    private func parseHandler() -> ParseNode? {
        let phase = consume()

        guard case let .identifier(name) = consume() else {
            error("expected event name after \(phase)")
            return nil
        }

        guard case .lparen = consume() else {
            error("expected ( after event handler name")
            return nil
        }

        var params = [Parameter]()
        while !match(.rparen) {
            guard case let .identifier(name) = consume() else {
                error("parameter name must be an identifier")
                return nil
            }

            guard let constraint = parsePrototype() else {
                return nil
            }

            params.append(Parameter(name: name, constraint: constraint))

            if currentToken != .rparen && !match(.comma) {
                error("expected , between function parameters")
            }
        }

        if let block = parseBlock() {
            return .handler(name, params, block)
        } else {
            return nil
        }
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
        default:
            return parseExpr()
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

    // MARK: - parsing expressions

    private func parseExpr(_ prec: Precedence = .assign) -> ParseNode? {
        var node: ParseNode?
        switch currentToken {
        case .boolean, .number, .string, .symbol:
            node = .literal(consume())
        case .identifier(let s):
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

        while let rule = Parser.parseRules[currentToken] {
            if prec <= rule.prec {
                node = rule.method!(self)(node!)
            } else {
                break
            }
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

        if case .string = currentToken {
            args.append(.literal(consume()))
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

        guard case let .identifier(name) = consume() else {
            error("expected identifier after :")
            return nil
        }

        guard let dir = Direction(rawValue: name) else {
            error("invalid direction \(name) after :")
            return nil
        }

        let _ = match(.oneway)  // FIXME:

        if !match(.to) {
            error("expected to after exit direction")
            return nil
        }

        guard let rhs = parseExpr(.or) else {
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
