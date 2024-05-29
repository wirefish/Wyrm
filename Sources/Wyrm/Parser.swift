//
// Parser.swift
// Wyrm
//

indirect enum ParseNode {
  typealias Member = (name: String, initialValue: ParseNode)
  typealias Handler = (EventPhase, String, [Parameter], ParseNode)
  typealias Method = (String, [Parameter], ParseNode)
  typealias QuestPhase = (String, [Member])

  // Literal values.
  case `nil`
  case boolean(Bool)
  case number(Double)
  case string(Text)
  case symbol(String)

  // Expressions.
  case identifier(String)
  case unaryExpr(Token, ParseNode)
  case binaryExpr(ParseNode, Token, ParseNode)
  case conjuction(ParseNode, ParseNode)
  case disjunction(ParseNode, ParseNode)
  case list([ParseNode])
  case clone(ParseNode, [Member])
  case call(ParseNode, [ParseNode])
  case dot(ParseNode, String)
  case `subscript`(ParseNode, ParseNode)
  case exit(ParseNode, ParseNode, ParseNode)
  case comprehension(ParseNode, String, ParseNode, ParseNode?)
  case stack(ParseNode, ParseNode)

  // Statements.
  case `var`(String, ParseNode)
  case `if`(ParseNode, ParseNode, ParseNode?)
  case `while`(ParseNode, ParseNode)
  case `for`(String, ParseNode, ParseNode)
  case await(ParseNode)
  case `return`(ParseNode?)
  case `fallthrough`
  case block([ParseNode])
  case assignment(ParseNode, Token, ParseNode)
  case ignoredValue(ParseNode)

  // Top-level definitions.
  case entity(name: String, prototype: ValueRef, members: [Member],
              handlers: [Handler], methods: [Method], isLocation: Bool)
  case quest(name: String, members: [Member], phases: [QuestPhase])
  case race(name: String, members: [Member])
  case skill(name: String, members: [Member])
  case region(members: [Member])
  case `extension`(ref: ValueRef, handlers: [Handler], methods: [Method])

  // True if this node can syntactically be on the left side of an assignment.
  var isAssignable: Bool {
    switch self {
    case .identifier(_): return true
    case .dot(_, _): return true
    case .subscript(_, _): return true
    default: return false
    }
  }

  var asValueRef: ValueRef? {
    switch self {
    case let .dot(lhs, name):
      guard case let .identifier(module) = lhs else {
        return nil
      }
      return .absolute(module, name)
    case let .identifier(name):
      return .relative(name)
    default:
      return nil
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
typealias InfixParseRule = (method: InfixParserMethod, prec: Precedence)

class Parser {
  static let parseRules: [Token:InfixParseRule] = [
    .lparen: (method: parseCall, prec: .call),
    .lsquare: (method: parseSubscript, prec: .call),
    .arrow: (method: parseExit, prec: .factor),
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
    .not: (method: parseClone, prec: .call),
    .notEqual: (method: parseBinary, prec: .equality),
    .equal: (method: parseAssignment, prec: .assign),
    .equalEqual: (method: parseBinary, prec: .equality),
    .less: (method: parseBinary, prec: .comparison),
    .lessEqual: (method: parseBinary, prec: .comparison),
    .greater: (method: parseBinary, prec: .comparison),
    .greaterEqual: (method: parseBinary, prec: .comparison),
    .and: (method: parseAnd, prec: .and),
    .or: (method: parseOr, prec: .or),
    .of: (method: parseStack, prec: .or),
  ]

  var scanner: Scanner
  var currentToken: Token = .endOfInput
  var errorCount = 0

  init(scanner: Scanner) {
    self.scanner = scanner
  }

  func parse() -> [ParseNode]? {
    advance()

    var nodes = [ParseNode]()
    while currentToken != .endOfInput {
      let token = consume()
      switch token {
      case .def:
        if let def = parseDefinition() {
          nodes.append(def)
        }
      case .extend:
        if let ext = parseExtension() {
          nodes.append(ext)
        }
      default:
        error("invalid token \(token) at top level")
      }
    }

    guard errorCount == 0 else {
      print("parsing failed with \(errorCount) errors")
      return nil
    }

    return nodes
  }

  private func parseDefinition() -> ParseNode? {
    guard case let .identifier(type) = consume() else {
      error("expected identifier after def")
      return nil
    }

    switch type {
    case "entity":
      return parseEntity(isLocation: false)
    case "location":
      return parseEntity(isLocation: true)
    case "region":
      return parseRegion()
    case "quest":
      return parseQuest()
    case "race":
      return parseRace()
    case "skill":
      return parseSkill()
    default:
      error("unknown type \(type) in definition")
      return nil
    }
  }

  // MARK: - parsing entities

  private func parseEntity(isLocation: Bool) -> ParseNode? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after def")
      return nil
    }

    guard match(.colon) else {
      error("prototype required for entity definition")
      return nil
    }

    guard let prototype = parseValueRef() else {
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of entity body")
      return nil
    }

    var members = [ParseNode.Member]()
    var handlers = [ParseNode.Handler]()
    var methods = [ParseNode.Method]()
    while !match(.rbrace) {
      switch currentToken {
      case .identifier:
        if let member = parseMember() {
          members.append(member)
        }
      case .allow, .before, .when, .after:
        if let handler = parseHandler() {
          handlers.append(handler)
        }
      case .func:
        if let method = parseMethod() {
          methods.append(method)
        }
      default:
        error("invalid token \(currentToken) within entity body")
        advance()
        break
      }
    }

    return .entity(name: name, prototype: prototype, members: members,
                   handlers: handlers, methods: methods,
                   isLocation: isLocation)
  }

  private func parseMember() -> ParseNode.Member? {
    guard case let .identifier(name) = consume() else {
      error("expected member name")
      return nil
    }

    guard case .equal = consume() else {
      error("expected = after member name")
      return nil
    }

    guard let initializer = parseExpr() else {
      return nil
    }

    return (name, initializer)
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

    var anonymousCount = 0
    let params = parseSequence(from: .lparen, until: .rparen) {
      () -> Parameter? in
      guard case var .identifier(name) = consume() else {
        error("parameter name must be an identifier")
        return nil
      }

      guard var constraint = parseConstraint() else {
        return nil
      }

      // As a special case, a parameter named self is just an anonymous parameter with
      // a self constraint.
      if name == "self" {
        if constraint == .none {
          constraint = .self
          name = "$\(anonymousCount)"
          anonymousCount += 1
        } else {
          error("parameter named self cannot have a constraint")
        }
      }

      return Parameter(name: name, constraint: constraint)
    }

    guard let block = parseBlock() else {
      return nil
    }

    return (phase, event, params, block)
  }

  private func parseMethod() -> ParseNode.Method? {
    assert(match(.func))

    guard case let .identifier(name) = consume() else {
      error("expected identifier after func")
      return nil
    }

    let params = parseSequence(from: .lparen, until: .rparen) {
      () -> Parameter? in
      guard case let .identifier(name) = consume() else {
        error("parameter name must be an identifier")
        return nil
      }
      if match(.colon) {
        error("method parameters cannot have constraints")
        return nil
      }
      return Parameter(name: name, constraint: .none)
    }

    guard let block = parseBlock() else {
      return nil
    }

    return (name, params, block)
  }

  private func parseConstraint() -> Constraint? {
    if !match(.colon) {
      return Constraint.none
    } else if match(.dot) {
      guard case let .identifier(constraintType) = consume() else {
        error("expected identifier after . in constraint")
        return nil
      }
      switch constraintType {
      case "quest":
        return parseQuestConstraint()
      default:
        error("invalid constraint type \(constraintType)")
        return nil
      }
    } else if let ref = parseValueRef() {
      return ref == .relative("self") ? .self : .prototype(ref)
    } else {
      return nil
    }
  }

  private func parseQuestConstraint() -> Constraint? {
    let params = parseSequence(from: .lparen, until: .rparen) { parseExpr() }
    guard params.count == 2,
          let questRef = params[0].asValueRef,
          case let .identifier(phase) = params[1] else {
      error("invalid quest constraint")
      return nil
    }
    return .quest(questRef, phase)
  }

  private func parseValueRef() -> ValueRef? {
    guard case let .identifier(prefix) = consume() else {
      error("identifier expected")
      return nil
    }
    if match(.dot) {
      guard case let .identifier(name) = consume() else {
        error("expected identifier after . in reference")
        return nil
      }
      return .absolute(prefix, name)
    } else {
      return .relative(prefix)
    }
  }

  // MARK: - parsing quests

  private func parseQuest() -> ParseNode? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after defquest")
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of quest body")
      return nil
    }

    var members = [ParseNode.Member]()
    var phases = [ParseNode.QuestPhase]()
    while !(match(.rbrace)) {
      switch currentToken {
      case .identifier:
        if let member = parseMember() {
          members.append(member)
        }
      case .phase:
        if let phase = parseQuestPhase() {
          phases.append(phase)
        }
        break
      default:
        error("unexpected token \(currentToken) in quest body")
        advance()
        break
      }
    }

    guard !phases.isEmpty else {
      error("quest \(name) does not define any phases")
      return nil
    }

    return .quest(name: name, members: members, phases: phases)
  }

  private func parseQuestPhase() -> ParseNode.QuestPhase? {
    assert(match(.phase))

    guard case let .identifier(label) = consume() else {
      error("expected identifier as name of quest phase")
      return nil
    }
    guard match(.lbrace) else {
      error("expected { at start of quest phase body")
      return nil
    }
    return (label, parseMembers())
  }

  // MARK: - parsing races

  private func parseRace() -> ParseNode? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after defrace")
      return nil
    }
    guard match(.lbrace) else {
      error("expected { at start of race body")
      return nil
    }
    return .race(name: name, members: parseMembers())
  }

  // MARK: - parsing skills

  private func parseSkill() -> ParseNode? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after defskill")
      return nil
    }
    guard match(.lbrace) else {
      error("expected { at start of skill body")
      return nil
    }
    return .skill(name: name, members: parseMembers())
  }

  // MARK: - parsing regions

  private func parseRegion() -> ParseNode? {
    guard match(.lbrace) else {
      error("expected { at start of region body")
      return nil
    }
    return .region(members: parseMembers())
  }

  private func parseMembers() -> [ParseNode.Member] {
    var members = [ParseNode.Member]()
    while !(match(.rbrace)) {
      if let member = parseMember() {
        members.append(member)
      }
    }
    return members
  }

  // MARK: - parsing extensions

  private func parseExtension() -> ParseNode? {
    guard let ref = parseValueRef() else {
      error("expected reference after extend")
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of extension body")
      return nil
    }

    var handlers = [ParseNode.Handler]()
    var methods = [ParseNode.Method]()
    while !match(.rbrace) {
      switch currentToken {
      case .allow, .before, .when, .after:
        if let handler = parseHandler() {
          handlers.append(handler)
        }
      case .func:
        if let method = parseMethod() {
          methods.append(method)
        }
      default:
        error("invalid token \(currentToken) within extension body")
        advance()
        break
      }
    }

    return .extension(ref: ref, handlers: handlers, methods: methods)
  }

  // MARK: - parsing statements

  private func parseStatement() -> ParseNode? {
    switch currentToken {
    case .var:
      return parseVar()
    case .if:
      return parseIf()
    case .while:
      return parseWhile()
    case .for:
      return parseFor()
    case .await:
      return parseAwait()
    case .return:
      return parseReturn()
    case .fallthrough:
      return parseFallthrough()
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
    guard let pred = parseExpr(), let whenTrue = parseBlock() else {
      return nil
    }
    var whenFalse: ParseNode?
    if match(.else) {
      whenFalse = (currentToken == .if) ? parseIf() : parseBlock()
      if whenFalse == nil {
        return nil
      }
    }
    return .if(pred, whenTrue, whenFalse)
  }

  private func parseWhile() -> ParseNode? {
    assert(match(.while))
    guard let pred = parseExpr(), let body = parseBlock() else {
      return nil
    }
    return .while(pred, body)
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
    guard let sequence = parseExpr(), let body = parseBlock() else {
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
    return .return(lookingAtExpr() ? parseExpr() : nil)
  }

  private func parseFallthrough() -> ParseNode {
    assert(match(.fallthrough))
    return .fallthrough
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

  private func lookingAtExpr() -> Bool {
    switch currentToken {
    case .nil, .boolean, .number, .string, .symbol, .identifier, .minus, .not, .star, .lparen, .lsquare:
      return true
    default:
      return false
    }
  }

  private func parseExpr(_ prec: Precedence = .or) -> ParseNode? {
    var node: ParseNode?
    switch currentToken {
    case .nil:
      node = .nil
      advance()
    case let .boolean(b):
      node = .boolean(b)
      advance()
    case let .number(n):
      node = .number(n)
      advance()
    case let .string(s):
      if let text = parseText(s) {
        node = .string(text)
      }
      advance()
    case let .symbol(s):
      node = .symbol(s)
      advance()
    case let .identifier(s):
      node = .identifier(s)
      advance()
    case .minus, .not, .star:
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
    if match(.rsquare) {
      return .list([])
    }

    guard let first = parseExpr() else {
      return nil
    }

    if match(.for) {
      // This is a list comprehension.
      guard case let .identifier(name) = consume() else {
        error("expected identifier after 'for' in list comprehension")
        return nil
      }
      guard match(.in) else {
        error("expected 'in' after variable name in list comprehension")
        return nil
      }
      guard let sequence = parseExpr() else {
        return nil
      }
      var pred: ParseNode?
      if match(.if) {
        pred = parseExpr()
        if pred == nil {
          return nil
        }
      }
      guard match(.rsquare) else {
        error("expected ] at end of list comprehension")
        return nil
      }
      return .comprehension(first, name, sequence, pred)
    } else {
      // This is a list literal.
      var items = [first]
      while !match(.rsquare) {
        if !match(.comma) {
          error(", expected between list values")
          return nil
        }
        guard let next = parseExpr() else {
          return nil
        }
        items.append(next)
      }
      return .list(items)
    }
  }

  private func parseClone(lhs: ParseNode) -> ParseNode? {
    assert(match(.not))

    // Parse optional member overrides.
    let members = if currentToken == .lbrace {
      parseSequence(from: .lbrace, until: .rbrace) { parseMember() }
    } else {
      [ParseNode.Member]()
    }

    return .clone(lhs, members)
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
    assert(match(.and))
    if let rhs = parseExpr(.and.nextHigher()) {
      return .conjuction(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseOr(lhs: ParseNode) -> ParseNode? {
    assert(match(.or))
    if let rhs = parseExpr(.or.nextHigher()) {
      return .disjunction(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseStack(lhs: ParseNode) -> ParseNode? {
    assert(match(.of))
    if let rhs = parseExpr(.or.nextHigher()) {
      return .stack(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseCall(lhs: ParseNode) -> ParseNode? {
    var args = parseSequence(from: .lparen, until: .rparen) { parseExpr() }

    // Allow for a trailing string/text literal as the final argument.
    if case let .string(s) = currentToken {
      advance()
      guard let text = parseText(s) else {
        return nil
      }
      args.append(.string(text))
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
    assert(match(.arrow))

    guard let direction = parseExpr() else {
      return nil
    }

    let _ = match(.oneway)  // FIXME:

    if !match(.to) {
      error("expected 'to' after exit direction")
      return nil
    }

    guard let destination = parseExpr() else {
      return nil
    }

    return .exit(lhs, direction, destination)
  }

  private func parseText(_ s: String) -> Text? {
    let parts = s.split(separator: "{", maxSplits: Int.max, omittingEmptySubsequences: false)

    var segments = [Text.Segment]()
    for part in parts.dropFirst() {
      let subparts = part.split(separator: "}", maxSplits: Int.max, omittingEmptySubsequences: false)
      guard subparts.count == 2 else {
        error("malformed text: \"\(s)\"")
        return nil
      }

      let state = pushScanner(Scanner(String(subparts[0])))
      defer { restoreScanner(state) }

      guard let expr = parseExpr() else {
        return nil
      }

      var format = Text.Format()
      if match(.colon) {
        guard case let .identifier(id) = consume(), id.count == 1, let spec = id.first else {
          error("malformed format specification")
          return nil
        }
        switch spec {
        case "i": format = [.indefinite]
        case "I": format = [.indefinite, .capitalized]
        case "d": format = [.definite]
        case "D": format = [.definite, .capitalized]
        case "n": format = []
        case "N": format = [.capitalized]
        default:
          error("invalid format specification")
          return nil
        }
      }

      segments.append(Text.Segment(expr: expr, format: format, suffix: String(subparts[1])))
    }

    return Text(prefix: String(parts[0]), segments: segments)
  }

  // Parses a comma-separated list of items enclosed within the specified start
  // and end tokens. The provided function is used to parse each item.
  private func parseSequence<T>(from start: Token?, until end: Token, _ fn: () -> T?) -> [T] {
    if start != nil && !match(start!) {
      error("expected \(start!) at \(currentToken)")
      return []
    }

    var items = [T]()
    while !match(end) {
      if let item = fn() {
        items.append(item)
      }
      if currentToken != end && !match(.comma) {
        error("expected , at \(currentToken)");
      }
    }

    return items
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

  private func pushScanner(_ newScanner: Scanner) -> (Scanner, Token) {
    let prevScanner = scanner
    let prevToken = currentToken
    scanner = newScanner
    advance()
    return (prevScanner, prevToken)
  }

  private func restoreScanner(_ state: (Scanner, Token)) {
    scanner = state.0
    currentToken = state.1
  }

  // MARK: - generating error messages

  private func error(_ message: String) {
    print("\(scanner.currentLine): \(message)")
    errorCount += 1
  }
}
