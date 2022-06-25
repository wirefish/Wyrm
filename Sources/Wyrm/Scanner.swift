//
//  Scanner.swift
//  Wyrm
//
//  Created by Craig Becker on 6/23/22.
//

enum Token: Hashable {
    case lparen, rparen, lsquare, rsquare, lbrace, rbrace
    case colon, comma, dot

    case minus, minusEqual, plus, plusEqual
    case slash, slashEqual, star, starEqual
    case percent, percentEqual

    case not, notEqual, equal, equalEqual
    case less, lessEqual, greater, greaterEqual
    case and, or, leads

    case def, deflocation
    case initializer, allow, before, after
    case `if`, `else`, `for`, `in`, `var`, oneway, to

    case boolean(Bool)
    case number(Double)
    case symbol(String)
    case string(String)
    case identifier(String)
    case ref(String?, String)

    case error(Int, String)
    case endOfInput
}

extension Character {
    var isDecimalDigit: Bool {
        return self >= "0" && self <= "9"
    }

    var isIdentifierChar: Bool {
        return self.isLetter || self == "_"
    }
}

class Scanner {
    private let input: String
    private var index: String.Index
    private var line = 1
    private let eof = Character("\0")

    init(_ input: String) {
        self.input = input
        index = self.input.startIndex
    }

    var currentLine: Int { line }

    func nextToken() -> Token {
        skipWhitespace()
        let ch = peek()
        if ch.isDecimalDigit {
            return scanNumber()
        } else if ch == "\"" {
            return scanString()
        } else if ch.isLetter {
            return scanIdentifier()
        } else {
            advance()
            switch ch {
            case eof: return .endOfInput
            case "(": return .lparen
            case ")": return .rparen
            case "[": return .lsquare
            case "]": return .rsquare
            case "{": return .lbrace
            case "}": return .rbrace
            case ":": return .colon
            case ",": return .comma
            case ".": return .dot
            case "'": return scanSymbol()
            case "@": return scanRef()
            case "-": return match("=") ? .minusEqual : match(">") ? .leads : .minus
            case "+": return match("=") ? .plusEqual : .plus
            case "*": return match("=") ? .starEqual : .star
            case "%": return match("=") ? .percentEqual : .percent
            case "!": return match("=") ? .notEqual : .not
            case "<": return match("=") ? .lessEqual : .less
            case ">": return match("=") ? .greaterEqual : .greater
            case "=": return match("=") ? .equalEqual : .equal

            case "/":
                if peek() == "*" || peek() == "/" {
                    skipComment()
                    return nextToken()
                } else {
                    return match("=") ? .slashEqual : .slash
                }

            case "&": return match("&") ? .and : .error(line, "unexpected character after &")

            case "|":
                if match("|") {
                    return .or
                } else if peek().isNewline {
                    advance()
                    return scanText()
                } else {
                    return .error(line, "unexpected character after |")
                }

            default:
                return .error(line, "unexpected character at \(ch)")
            }
        }
    }

    private func peek() -> Character {
        return index < input.endIndex ? input[index] : eof
    }

    @discardableResult
    private func advance() -> Character {
        let ch = peek()
        if ch != eof {
            index = input.index(after: index)
            if ch.isNewline {
                line += 1
            }
        }
        return ch
    }

    private func match(_ ch: Character) -> Bool {
        if peek() == ch {
            advance()
            return true
        } else {
            return false
        }
    }

    private func skipWhitespace() {
        while true {
            if peek().isWhitespace {
                advance()
            } else {
                break
            }
        }
    }

    private func skipComment() {
        if match("*") {
            // Skip until the next "*/".
            while advance() != "*" || peek() != "/" { }
        } else if match("/") {
            // Skip until the end of this line.
            while !advance().isNewline { }
        }
    }

    private func scanNumber() -> Token {
        let start = index
        while peek().isDecimalDigit {
            advance()
        }
        if match(".") {
            while peek().isDecimalDigit {
                advance()
            }
        }
        return .number(Double(input[start..<index])!)
    }

    private func scanString() -> Token {
        advance()  // past leading double quote
        let start = index
        while index < input.endIndex && peek() != "\"" {
            let ch = advance()
            if ch == "\\" {
                advance()
            }
        }
        if index == input.endIndex {
            return .error(line, "unterminated string literal")
        } else {
            let token = Token.string(String(input[start..<index]))
            advance()  // past ending double quote
            return token
        }
    }

    private func scanIndent() -> Int {
        var indent = 0
        while peek().isWhitespace && !peek().isNewline {
            advance()
            indent += 1
        }
        return indent
    }

    private func scanText() -> Token {
        let baseIndent = scanIndent()
        var result = ""
        while index < input.endIndex {
            let start = index
            while !advance().isNewline { }
            result.append(contentsOf: input[start..<index])
            let indent = scanIndent()
            if peek().isNewline {
            } else if indent < baseIndent {
                break
            } else if indent > baseIndent {
                result.append(contentsOf: String(repeating: " ", count: indent - baseIndent))
            }
        }
        return .string(result)
    }

    private let keywords: [String:Token] = [
        "true": .boolean(true),
        "false": .boolean(false),
        "def": .def,
        "deflocation": .deflocation,
        "init": .initializer,
        "allow": .allow,
        "before": .before,
        "after": .after,
        "if": .if,
        "else": .else,
        "for": .for,
        "in": .in,
        "var": .var,
        "oneway": .oneway,
        "to": .to,
    ]

    private func consumeIdentifier() -> String? {
        let start = index
        if peek().isIdentifierChar {
            advance()
            while peek().isIdentifierChar || peek().isNumber {
                advance()
            }
            return String(input[start..<index])
        } else {
            return nil
        }
    }

    private func scanIdentifier() -> Token {
        guard let id = consumeIdentifier() else {
            return .error(line, "invalid identifier")
        }
        return keywords[id] ?? .identifier(id)
    }

    private func scanSymbol() -> Token {
        // Note the leading ' has already been consumed.
        guard let id = consumeIdentifier() else {
            return .error(line, "invalid symbolic constant")
        }
        return .symbol(id)
    }

    private func scanRef() -> Token {
        // A reference can look like @name or @namespace.name. Note the leading @
        // has already been consumed.
        guard let id = consumeIdentifier() else {
            return .error(line, "invalid reference")
        }
        if match(".") {
            guard let name = consumeIdentifier() else {
                return .error(line, "invalid name in reference")
            }
            return .ref(id, name)
        } else {
            return .ref(nil, id)
        }
    }
}
