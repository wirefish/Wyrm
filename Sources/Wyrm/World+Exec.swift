//
//  World+Exec.swift
//  Wyrm
//

enum ExecError: Error {
  case typeMismatch
  case undefinedSymbol(String)
  case undefinedReference(Ref)
  case indexOutOfBounds
  case referenceRequired
  case expectedCallable
  case expectedFuture
  case invalidResult
  case nestedIterationNotSupported
}

enum ValueIterator {
  case range(ClosedRange<Int>.Iterator)
  case array(Array<Value>.Iterator)

  mutating func next() -> Value? {
    switch self {
    case var .range(it):
      let value = it.next()?.toValue()
      self = .range(it)
      return value
    case var .array(it):
      let value = it.next()
      self = .array(it)
      return value
    }
  }
}

extension World {
  func exec(_ code: ScriptFunction, args: [Value], context: [Scope]) throws -> CallableResult {
    // The arguments are always the first locals, and self is always the first argument.
    // Subsequent locals start with no value.
    var locals = args
    var stack = [Value]()
    return try resume(code, context, &locals, &stack, 0)
  }

  func resume(_ code: ScriptFunction, _ context: [Scope], _ locals: inout [Value],
              _ stack: inout [Value], _ ip: Int) throws -> CallableResult {
    var lists = [Int]()
    var ip = ip
    var iter: ValueIterator?

    while ip < code.bytecode.count {
      let op = Opcode(rawValue: code.bytecode[ip])!
      ip += 1
      switch op {

      case .pushNil: stack.append(.nil)

      case .pushTrue: stack.append(.boolean(true))

      case .pushFalse: stack.append(.boolean(false))

      case .pushSmallInt:
        let v = Int8(bitPattern: code.bytecode[ip])
        stack.append(.number(Double(v)))
        ip += 1

      case .pushConstant:
        let index = code.getUInt16(at: ip)
        stack.append(code.constants[Int(index)])
        ip += 2

      case .pop:
        let _ = stack.removeLast()

      case .dup:
        stack.append(stack.last!)

      case .createLocal:
        locals.append(stack.removeLast())

      case .removeLocals:
        let count = Int(code.bytecode[ip]); ip += 1
        locals.removeLast(count)

      case .loadLocal:
        let index = Int(code.bytecode[ip]); ip += 1
        stack.append(locals[index])

      case .storeLocal:
        let index = Int(code.bytecode[ip]); ip += 1
        locals[index] = stack.removeLast()

      case .not:
        guard case let .boolean(b) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        stack.append(.boolean(!b))

      case .negate:
        guard case let .number(n) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        stack.append(.number(-n))

      case .deref:
        guard case let .ref(ref) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        guard let value = World.instance.lookup(ref, context: context) else {
          throw ExecError.undefinedReference(ref)
        }
        stack.append(value)

      case .select:
        switch stack.removeLast() {
        case let .list(list): stack.append(list.randomElement().toValue())
        case let .range(range): stack.append(range.randomElement().toValue())
        default: throw ExecError.typeMismatch
        }

      case .add, .subtract, .multiply, .divide, .modulus:
        let rhs = stack.removeLast()
        let lhs = stack.removeLast()
        guard case let .number(a) = lhs, case let .number(b) = rhs else {
          throw ExecError.typeMismatch
        }
        switch op {
        case .add: stack.append(.number(a + b))
        case .subtract: stack.append(.number(a - b))
        case .multiply: stack.append(.number(a * b))
        case .divide: stack.append(.number(a / b))
        case .modulus: stack.append(.number(a.truncatingRemainder(dividingBy: b)))
        default: break
        }

      case .equal:
        let rhs = stack.removeLast()
        let lhs = stack.removeLast()
        stack.append(.boolean(lhs == rhs))

      case .notEqual:
        let rhs = stack.removeLast()
        let lhs = stack.removeLast()
        stack.append(.boolean(lhs != rhs))

      case .less, .lessEqual, .greater, .greaterEqual:
        let rhs = stack.removeLast()
        let lhs = stack.removeLast()
        guard case let .number(a) = lhs, case let .number(b) = rhs else {
          throw ExecError.typeMismatch
        }
        switch op {
        case .less: stack.append(.boolean(a < b))
        case .lessEqual: stack.append(.boolean(a <= b))
        case .greater: stack.append(.boolean(a > b))
        case .greaterEqual: stack.append(.boolean(a >= b))
        default: break
        }

      case .jump:
        let offset = code.getInt16(at: ip)
        ip += 2 + Int(offset)

      case .jumpIfTrue:
        guard case let .boolean(b) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        if (b) {
          let offset = code.getInt16(at: ip)
          ip += 2 + Int(offset)
        } else {
          ip += 2
        }

      case .jumpIfFalse:
        guard case let .boolean(b) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        if (!b) {
          let offset = code.getInt16(at: ip)
          ip += 2 + Int(offset)
        } else {
          ip += 2
        }

      case .loadSymbol:
        let index = code.getUInt16(at: ip)
        guard case let .symbol(s) = code.constants[Int(index)] else {
          throw ExecError.typeMismatch
        }
        guard let value = lookup(.relative(s), context: context) else {
          throw ExecError.undefinedSymbol(s)
        }
        stack.append(value)
        ip += 2

      case .loadMember:
        let index = code.getUInt16(at: ip); ip += 2
        let lhs = stack.removeLast()
        guard case let .symbol(name) = code.constants[Int(index)],
              let dict = lhs.asScope else {
          throw ExecError.typeMismatch
        }
        guard let value = dict.get(name) else {
          throw ExecError.undefinedSymbol(name)
        }
        if case let .function(fn) = value {
          guard case let .entity(entity) = lhs else {
            throw ExecError.typeMismatch
          }
          stack.append(.function(BoundMethod(object: entity, method: fn)))
        } else {
          stack.append(value)
        }

      case .storeMember:
        let index = code.getUInt16(at: ip)
        guard case let .symbol(name) = code.constants[Int(index)] else {
          throw ExecError.typeMismatch
        }
        let value = stack.removeLast()
        guard let dict = stack.removeLast().asScope else {
          throw ExecError.typeMismatch
        }
        try dict.set(name, to: value)
        ip += 2

      case .loadSubscript:
        guard let index = Int.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        guard case let .list(list) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        guard index >= 0 && index < list.count else {
          throw ExecError.indexOutOfBounds
        }
        stack.append(list[index])

      case .storeSubscript:
        let rhs = stack.removeLast()
        guard let index = Int.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        guard case var .list(list) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        list[index] = rhs

      case .beginList:
        lists.append(stack.count)

      case .endList:
        let start = lists.removeLast()
        let values = Array<Value>(stack[start...])
        stack.removeSubrange(start...)
        stack.append(.list(values))

      case .makeRange:
        guard let upperBound = Int.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        guard let lowerBound = Int.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        stack.append(.range(lowerBound...upperBound))

      case .makeIterator:
        guard iter == nil else {
          throw ExecError.nestedIterationNotSupported
        }
        switch stack.removeLast() {
        case let .list(list): iter = .array(list.makeIterator())
        case let .range(range): iter = .range(range.makeIterator())
        default: throw ExecError.typeMismatch
        }

      case .advanceOrJump:
        if let value = iter?.next() {
          stack.append(value.toValue())
          ip += 2
        } else {
          iter = nil
          ip += Int(code.getInt16(at: ip)) + 2
        }

      case .makePortal:
        guard let dest = stack.removeLast().asEntity(Location.self),
              let dir = Direction.fromValue(stack.removeLast()),
              let proto = stack.removeLast().asEntity(Portal.self) else {
          throw ExecError.typeMismatch
        }
        let portal = proto.clone()
        portal.direction = dir
        portal.destination = dest
        stack.append(.entity(portal))

      case .clone:
        let value = stack.removeLast()
        guard case let .entity(e) = value else {
          throw ExecError.typeMismatch
        }
        stack.append(.entity(e.clone()))

      case .makeStack:
        guard let item = Item.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        guard let count = Int.fromValue(stack.removeLast()) else {
          throw ExecError.typeMismatch
        }
        stack.append(ItemStack(item: item, count: count).toValue())

      case .call:
        guard case let .list(args) = stack.removeLast() else {
          throw ExecError.typeMismatch
        }
        guard case let .function(fn) = stack.removeLast() else {
          throw ExecError.expectedCallable
        }
        guard case let .value(value) = try fn.call(args, context: []) else {
          // await and fallthrough are not supported results from nested calls.
          throw ExecError.invalidResult
        }
        stack.append(value)

      case .stringify:
        let format = Format(rawValue: code.bytecode[ip])
        let s = stringify(value: stack.removeLast(), format: format)
        stack.append(.string(s))
        ip += 1

      case .joinStrings:
        let count = Int(code.bytecode[ip])
        let joined = try stack.suffix(count).map({
          guard case let .string(s) = $0 else {
            throw ExecError.typeMismatch
          }
          return s
        }).joined()
        stack.removeLast(count)
        stack.append(.string(joined))
        ip += 1

      case .await:
        guard case let .future(future) = stack.removeLast() else {
          throw ExecError.expectedFuture
        }
        var futureLocals = locals.map { $0 }
        var futureStack = stack.map { $0 }
        future {
          do {
            _ = try self.resume(code, context, &futureLocals, &futureStack, ip)
          } catch {
            logger.warning("error in resumed function: \(error)")
          }
        }
        return .await

      case .return:
        return .value(stack.last ?? .nil)

      case .fallthrough:
        return .fallthrough
      }
    }

    assert(stack.isEmpty)
    return .value(.nil)
  }

  private func stringify(value: Value, format: Format) -> String {
    switch value {
    case .nil:
      return "nil"
    case let .boolean(b):
      return b ? "true" : "false"
    case let .number(n):
      return String(n)
    case let .string(s):
      return s
    case let .symbol(s):
      return "'\(s)"
    case let .entity(e):
      if let v = e as? Viewable {
        return v.describeBriefly(format)
      } else {
        return String(describing: e)
      }
    case let .race(r):
      return r.describeBriefly(format)
    default:
      return String(describing: value)
    }
  }
}
