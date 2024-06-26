//
//  Parser.swift
//  Wyrm
//

enum StringSegment {
  case string(String)
  case expr(Expression, Format)
}

indirect enum Expression {
  typealias Member = (name: String, initializer: Expression)

  case `nil`
  case boolean(Bool)
  case number(Double)
  case string(String)
  case symbol(String)

  case identifier(String)
  case interpolatedString([StringSegment])
  case unaryExpr(Token, Expression)
  case binaryExpr(Expression, Token, Expression)
  case conjuction(Expression, Expression)
  case disjunction(Expression, Expression)
  case list([Expression])
  case clone(Expression, [Member])
  case call(Expression, [Expression])
  case dot(Expression, String)
  case `subscript`(Expression, Expression)
  case exit(Expression, Expression, Expression)
  case comprehension(Expression, String, Expression, Expression?)
  case stack(Expression, Expression)

  // True if this expression can syntactically be on the left side of an
  // assignment.
  var isAssignable: Bool {
    switch self {
    case .identifier, .dot, .subscript:
      return true
    default:
      return false
    }
  }

  var asRef: Ref? {
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

indirect enum Statement {
  case `var`(String, Expression)
  case `if`(Expression, Statement, Statement?)
  case `while`(Expression, Statement)
  case `for`(String, Expression, Statement)
  case await(Expression)
  case `return`(Expression?)
  case `fallthrough`
  case block([Statement])
  case assignment(Expression, Token, Expression)
  case ignoredValue(Expression)
}

enum Definition {
  typealias Member = Expression.Member
  typealias Handler = (Event, [Parameter], Statement)
  typealias Function = (String, [Parameter], Statement)
  typealias QuestPhase = (String, [Member])

  case function(Function)
  case entity(name: String, prototype: Ref, members: [Member],
              handlers: [Handler], methods: [Function], isLocation: Bool)
  case quest(name: String, members: [Member], phases: [QuestPhase])
  case race(name: String, members: [Member])
  case skill(name: String, members: [Member])
  case region(members: [Member])
  case `extension`(ref: Ref, handlers: [Handler], methods: [Function])
}

enum Precedence: Int, Comparable {
  case none = 0
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

typealias InfixParserMethod = (Parser) -> (_ lhs: Expression) -> Expression?
typealias InfixParseRule = (method: InfixParserMethod, prec: Precedence)

class Parser {
  static let parseRules: [Token:InfixParseRule] = [
    .lparen: (method: parseCall, prec: .call),
    .lsquare: (method: parseSubscript, prec: .call),
    .arrow: (method: parseExit, prec: .factor),
    .dot: (method: parseDot, prec: .call),
    .range: (method: parseBinary, prec: .comparison),
    .at: (method: parseStack, prec: .factor),
    .minus: (method: parseBinary, prec: .term),
    .plus: (method: parseBinary, prec: .term),
    .slash: (method: parseBinary, prec: .factor),
    .star: (method: parseBinary, prec: .factor),
    .percent: (method: parseBinary, prec: .factor),
    .not: (method: parseClone, prec: .call),
    .notEqual: (method: parseBinary, prec: .equality),
    .equalEqual: (method: parseBinary, prec: .equality),
    .less: (method: parseBinary, prec: .comparison),
    .lessEqual: (method: parseBinary, prec: .comparison),
    .greater: (method: parseBinary, prec: .comparison),
    .greaterEqual: (method: parseBinary, prec: .comparison),
    .and: (method: parseAnd, prec: .and),
    .or: (method: parseOr, prec: .or),
  ]

  var scanner: Scanner
  var currentToken: Token = .endOfInput
  var errorCount = 0

  init(scanner: Scanner) {
    self.scanner = scanner
  }

  func parse() -> [Definition]? {
    advance()

    var defs = [Definition]()
    while currentToken != .endOfInput {
      let token = consume()
      switch token {
      case .func:
        if let fn = parseFunction() {
          defs.append(.function(fn))
        }
      case .def:
        if let def = parseDefinition() {
          defs.append(def)
        }
      case .extend:
        if let ext = parseExtension() {
          defs.append(ext)
        }
      default:
        error("invalid token \(token) at top level")
      }
    }

    guard errorCount == 0 else {
      print("parsing failed with \(errorCount) errors")
      return nil
    }

    return defs
  }

  func parseSingleStatement() -> Statement? {
    advance()
    var stmt = parseStatement()
    if case let .ignoredValue(expr) = stmt {
      stmt = .return(expr)
    }
    return stmt
  }

  private func parseDefinition() -> Definition? {
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

  private func parseEntity(isLocation: Bool) -> Definition? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after def")
      return nil
    }

    guard match(.colon) else {
      error("prototype required for entity definition")
      return nil
    }

    guard let prototype = parseRef() else {
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of entity body")
      return nil
    }

    var members = [Definition.Member]()
    var handlers = [Definition.Handler]()
    var methods = [Definition.Function]()
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
        advance()
        if let method = parseFunction() {
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

  private func parseMember() -> Definition.Member? {
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

  private func parseHandler() -> Definition.Handler? {
    var phase: Event.Phase
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

    return (Event(phase: phase, name: event), params, block)
  }

  private func parseFunction() -> Definition.Function? {
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
    } else if let ref = parseRef() {
      return ref == .relative("self") ? .self : .prototype(ref)
    } else {
      return nil
    }
  }

  private func parseQuestConstraint() -> Constraint? {
    let params = parseSequence(from: .lparen, until: .rparen) { parseExpr() }
    guard params.count == 2,
          let questRef = params[0].asRef,
          case let .identifier(phase) = params[1] else {
      error("invalid quest constraint")
      return nil
    }
    return .quest(questRef, phase)
  }

  private func parseRef() -> Ref? {
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

  private func parseQuest() -> Definition? {
    guard case let .identifier(name) = consume() else {
      error("expected identifier after defquest")
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of quest body")
      return nil
    }

    var members = [Definition.Member]()
    var phases = [Definition.QuestPhase]()
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

  private func parseQuestPhase() -> Definition.QuestPhase? {
    advance()

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

  private func parseRace() -> Definition? {
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

  private func parseSkill() -> Definition? {
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

  private func parseRegion() -> Definition? {
    guard match(.lbrace) else {
      error("expected { at start of region body")
      return nil
    }
    return .region(members: parseMembers())
  }

  private func parseMembers() -> [Definition.Member] {
    var members = [Definition.Member]()
    while !(match(.rbrace)) {
      if let member = parseMember() {
        members.append(member)
      }
    }
    return members
  }

  // MARK: - parsing extensions

  private func parseExtension() -> Definition? {
    guard let ref = parseRef() else {
      error("expected reference after extend")
      return nil
    }

    guard match(.lbrace) else {
      error("expected { at start of extension body")
      return nil
    }

    var handlers = [Definition.Handler]()
    var methods = [Definition.Function]()
    while !match(.rbrace) {
      switch currentToken {
      case .allow, .before, .when, .after:
        if let handler = parseHandler() {
          handlers.append(handler)
        }
      case .func:
        advance()
        if let method = parseFunction() {
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

  private func parseStatement() -> Statement? {
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
      guard let expr = parseExpr() else {
        return nil;
      }
      return currentToken.isAssignment ? parseAssignment(lhs : expr) : .ignoredValue(expr)
    }
  }

  private func parseVar() -> Statement? {
    advance()

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

  private func parseIf() -> Statement? {
    advance()
    guard let pred = parseExpr(), let whenTrue = parseBlock() else {
      return nil
    }
    var whenFalse: Statement?
    if match(.else) {
      whenFalse = (currentToken == .if) ? parseIf() : parseBlock()
      if whenFalse == nil {
        return nil
      }
    }
    return .if(pred, whenTrue, whenFalse)
  }

  private func parseWhile() -> Statement? {
    advance()
    guard let pred = parseExpr(), let body = parseBlock() else {
      return nil
    }
    return .while(pred, body)
  }

  private func parseFor() -> Statement? {
    advance()
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

  private func parseBlock() -> Statement? {
    guard case .lbrace = consume() else {
      error("expected { at beginning of block")
      return nil
    }
    var stmts = [Statement]()
    while !match(.rbrace) {
      if let stmt = parseStatement() {
        stmts.append(stmt)
      } else {
        return nil
      }
    }
    return .block(stmts)
  }

  private func parseAwait() -> Statement? {
    advance()
    guard let rhs = parseExpr() else {
      return nil
    }
    return .await(rhs)
  }

  private func parseReturn() -> Statement? {
    advance()
    return .return(lookingAtExpr() ? parseExpr() : nil)
  }

  private func parseFallthrough() -> Statement {
    advance()
    return .fallthrough
  }

  private func parseAssignment(lhs: Expression) -> Statement? {
    let op = consume()
    guard let rhs = parseExpr() else {
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

  private func parseExpr(_ prec: Precedence = .or) -> Expression? {
    var node: Expression?
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
    case .string:
      node = parseString()
    case let .symbol(s):
      node = .symbol(s)
      advance()
    case let .identifier(s):
      node = .identifier(s)
      advance()
    case .minus, .not, .query:
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

    return node
  }

  private func parseUnary() -> Expression? {
    let op = consume()
    if let rhs = parseExpr(.unary) {
      return .unaryExpr(op, rhs)
    } else {
      return nil
    }
  }

  private func parseGroup() -> Expression? {
    advance()
    if let expr = parseExpr() {
      if match(.rparen) {
        return expr
      } else {
        error("expected ) after expression")
      }
    }
    return nil
  }

  private func parseList() -> Expression? {
    advance()
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
      var pred: Expression?
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

  private func parseClone(lhs: Expression) -> Expression? {
    advance()

    // Parse optional member overrides.
    let members = if currentToken == .lbrace {
      parseSequence(from: .lbrace, until: .rbrace) { parseMember() }
    } else {
      [Expression.Member]()
    }

    return .clone(lhs, members)
  }

  private func parseBinary(lhs: Expression) -> Expression? {
    let op = consume()
    if let rhs = parseExpr(Parser.parseRules[op]!.prec.nextHigher()) {
      return .binaryExpr(lhs, op, rhs)
    } else {
      return nil
    }
  }

  private func parseAnd(lhs: Expression) -> Expression? {
    advance()
    if let rhs = parseExpr(.and.nextHigher()) {
      return .conjuction(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseOr(lhs: Expression) -> Expression? {
    advance()
    if let rhs = parseExpr(.or.nextHigher()) {
      return .disjunction(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseStack(lhs: Expression) -> Expression? {
    advance()
    if let rhs = parseExpr(.factor.nextHigher()) {
      return .stack(lhs, rhs)
    } else {
      return nil
    }
  }

  private func parseCall(lhs: Expression) -> Expression? {
    var args = parseSequence(from: .lparen, until: .rparen) { parseExpr() }

    // Allow for a trailing string/text literal as the final argument.
    if case .string = currentToken {
      guard let trailingString = parseString() else {
        return nil
      }
      args.append(trailingString)
    }

    return .call(lhs, args)
  }

  private func parseSubscript(lhs: Expression) -> Expression? {
    advance()

    guard let expr = parseExpr() else {
      return nil
    }

    guard case .rsquare = consume() else {
      error("expected ] after subscript expression")
      return nil
    }

    return .subscript(lhs, expr)
  }

  private func parseDot(lhs: Expression) -> Expression? {
    advance()

    guard case let .identifier(name) = consume() else {
      error("expected identifier after .")
      return nil
    }

    return .dot(lhs, name)
  }

  private func parseExit(lhs: Expression) -> Expression? {
    advance()

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

  // Parses a string that may contain interpolation expressions.
  private func parseString() -> Expression? {
    guard case let .string(s) = consume() else {
      error("expected string")
      return nil
    }

    let parts = s.split(separator: "{", omittingEmptySubsequences: false)
    if parts.count == 1 {
      // This is a literal with no interpolation required.
      return .string(s)
    }

    // The first (possibly empty) part is always a string literal.
    var segments = [StringSegment]()
    if !parts.first!.isEmpty {
      segments.append(.string(String(parts.first!)))
    }

    // Each subseqent part contains a } which separates a leading expression from
    // a trailing (possibily empty) string literal.
    for part in parts.dropFirst() {
      let subparts = part.split(separator: "}", omittingEmptySubsequences: false)
      guard subparts.count == 2 else {
        if subparts.count == 1 {
          error("string contains { without matching }")
        } else {
          error("string contains } without matching {")
        }
        return nil
      }

      let state = pushScanner(Scanner(String(subparts[0])))
      defer { restoreScanner(state) }

      guard let expr = parseExpr() else {
        return nil
      }

      var format = Format()
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

      segments.append(.expr(expr, format))
      if !subparts[1].isEmpty {
        segments.append(.string(String(subparts[1])))
      }
    }

    return .interpolatedString(segments)
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
