//
//  Scanner.swift
//  Wyrm
//

enum Token: Hashable {
  case lparen, rparen, lsquare, rsquare, lbrace, rbrace
  case colon, comma, dot, at

  case minus, minusEqual, plus, plusEqual
  case slash, slashEqual, star, starEqual
  case percent, percentEqual

  case not, notEqual, equal, equalEqual
  case less, lessEqual, greater, greaterEqual
  case and, or

  case def, extend
  case allow, before, when, after, phase, `func`
  case `if`, `else`, `while`, `for`, `in`, `let`, `var`
  case await, `return`, `fallthrough`
  case arrow, oneway, to

  case `nil`
  case boolean(Bool)
  case number(Double)
  case symbol(String)
  case string(String)
  case identifier(String)

  case error(Int, String)
  case endOfInput

  var isAssignment: Bool {
    return (self == .minusEqual || self == .plusEqual || self == .starEqual ||
            self == .slashEqual || self == .percentEqual || self == .equal)
  }
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
  private var lineNumber = 1
  private let eof = Character("\0")

  init(_ input: String) {
    self.input = input
    index = self.input.startIndex
  }

  var currentLine: Int { lineNumber }

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
      case "@": return .at
      case "'": return scanSymbol()
      case "-": return match("=") ? .minusEqual : match(">") ? .arrow : .minus
      case "+": return match("=") ? .plusEqual : .plus
      case "*": return match("=") ? .starEqual : .star
      case "%": return match("=") ? .percentEqual : .percent
      case "!": return match("=") ? .notEqual : .not
      case "<": return match("=") ? .lessEqual : .less
      case ">": return match("=") ? .greaterEqual : .greater
      case "=": return match("=") ? .equalEqual : .equal
      case "&": return match("&") ? .and : .error(lineNumber, "unexpected character after &")
      case "|": return match("|") ? .or : .error(lineNumber, "unexpected character after |")

      case "/":
        if peek() == "*" || peek() == "/" {
          skipComment()
          return nextToken()
        } else {
          return match("=") ? .slashEqual : .slash
        }

      default:
        return .error(lineNumber, "unexpected character at \(ch)")
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
        lineNumber += 1
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
    while peek().isWhitespace {
      advance()
    }
  }

  private func skipComment() {
    if match("*") {
      // Skip until the next "*/".
      while advance() != "*" || !match("/") {}
    } else if match("/") {
      // Skip until the next line.
      while !advance().isNewline {}
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

    if match("\"") {
      return match("\"") ? scanMultilineString() : .string("")
    }

    while index < input.endIndex && peek() != "\"" {
      let ch = advance()
      if ch == "\n" {
        return .error(lineNumber, "newline in single-line string literal")
      } else if ch == "\\" {
        // FIXME: handle escape chars
        advance()
      }
    }
    if index == input.endIndex {
      return .error(lineNumber, "unterminated string literal")
    } else {
      let token = Token.string(String(input[start..<index]))
      advance()  // past ending double quote
      return token
    }
  }

  private func scanMultilineString() -> Token {
    let delimiter = "\"\"\""

    let firstLineNumber = lineNumber
    let startsWithNewline = match("\n")

    // Consume input up to and including the ending """.
    var lines = [Substring]()
    var last : Substring!
    while (index < input.endIndex && last == nil) {
      guard let eol = input[index...].firstIndex(where: { $0.isNewline }) else {
        index = input.endIndex
        return .error(lineNumber, "missing newline in multi-line string")
      }
      let line = input[index...eol]
      if let r = line.range(of: delimiter) {
        last = line[..<r.lowerBound]
        index = r.upperBound
      } else {
        lines.append(line)
        index = input.index(after: eol)
        lineNumber += 1
      }
    }
    guard last != nil else {
      return .error(lineNumber, "unterminated muilti-line string")
    }

    // Now that the string has been consumed, flag an error if it didn't start
    // with a newline after the opening """.
    if !startsWithNewline {
      return .error(firstLineNumber,
                    "newline expected after \(delimiter) at start of multi-line string")
    }

    // The last line has had the """ and anything following it removed. It
    // should be only whitespace, and its length determines the string
    // indentation.
    guard last.firstIndex(where: { !$0.isWhitespace }) == nil else {
      return .error(lineNumber,
                    "unexpected characters before \(delimiter) at end of multi-line string")
    }
    let blockIndent = last.count

    // Build up the result by removing the required amount of whitespace from
    // the beginning of each line and concatenating what's left.
    var result = ""
    for line in lines {
      if let p = line.firstIndex(where: { !$0.isWhitespace }) {
        let lineIndent = line.distance(from: line.startIndex, to: p)
        guard lineIndent >= blockIndent else {
          return .error(lineNumber, "invalid indentation in multi-line string")
        }
        // FIXME: handle escape characters
        result.append(contentsOf: line.dropFirst(blockIndent))
      } else {
        result.append("\n")
      }
    }

    return .string(result)
  }

  private let keywords: [String:Token] = [
    "nil": .nil,
    "true": .boolean(true),
    "false": .boolean(false),
    "def": .def,
    "extend": .extend,
    "allow": .allow,
    "before": .before,
    "when": .when,
    "after": .after,
    "phase": .phase,
    "func": .func,
    "if": .if,
    "else": .else,
    "while": .while,
    "for": .for,
    "in": .in,
    "let": .let,
    "var": .var,
    "await": .await,
    "return": .return,
    "fallthrough": .fallthrough,
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
      return .error(lineNumber, "invalid identifier")
    }
    return keywords[id] ?? .identifier(id)
  }

  private func scanSymbol() -> Token {
    // Note the leading ' has already been consumed.
    guard let id = consumeIdentifier() else {
      return .error(lineNumber, "invalid symbolic constant")
    }
    return .symbol(id)
  }
}
