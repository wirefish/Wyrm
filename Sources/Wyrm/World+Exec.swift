//
//  World+Exec.swift
//  Wyrm
//

enum ExecError: Error {
    case typeMismatch
    case undefinedSymbol(String)
    case expectedCallable
    case expectedFuture
    case invalidResult
}

extension ScriptFunction {
    func getUInt16(at offset: Int) -> UInt16 {
        UInt16(bytecode[offset]) | (UInt16(bytecode[offset + 1]) << 8)
    }

    func getInt16(at offset: Int) -> Int16 {
        Int16(bitPattern: getUInt16(at: offset))
    }
}

extension World {
    func exec(_ code: ScriptFunction, args: [Value], context: [ValueDictionary]) throws -> CallableResult {
        // The arguments are always the first locals, and self is always the first argument.
        // Subsequent locals start with no value.
        var locals = args
        locals += Array<Value>(repeating: .nil, count: code.locals.count - args.count)
        var stack = [Value]()
        return try resume(code, context, &locals, &stack, 0)
    }

    func resume(_ code: ScriptFunction, _ context: [ValueDictionary], _ locals: inout [Value],
                _ stack: inout [Value], _ ip: Int) throws -> CallableResult {
        var ip = ip
        loop: while ip < code.bytecode.count {
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

            case .pushLocal:
                let index = Int(code.bytecode[ip])
                stack.append(locals[index])
                ip += 1

            case .popLocal:
                let index = Int(code.bytecode[ip])
                locals[index] = stack.removeLast()
                ip += 1

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

            case .equal, .notEqual:
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                switch lhs {
                case let .boolean(a):
                    guard case let .boolean(b) = rhs else {
                        throw ExecError.typeMismatch
                    }
                    switch op {
                    case .equal: stack.append(.boolean(a == b))
                    case .notEqual: stack.append(.boolean(a != b))
                    default: break
                    }

                case let .number(a):
                    guard case let .number(b) = rhs else {
                        throw ExecError.typeMismatch
                    }
                    switch op {
                    case .equal: stack.append(.boolean(a == b))
                    case .notEqual: stack.append(.boolean(a != b))
                    default: break
                    }

                case let .symbol(a):
                    guard case let .symbol(b) = rhs else {
                        throw ExecError.typeMismatch
                    }
                    switch op {
                    case .equal: stack.append(.boolean(a == b))
                    case .notEqual: stack.append(.boolean(a != b))
                    default: break
                    }

                case let .entity(a):
                    guard case let .entity(b) = rhs else {
                        throw ExecError.typeMismatch
                    }
                    switch op {
                    case .equal: stack.append(.boolean(a == b))
                    case .notEqual: stack.append(.boolean(a != b))
                    default: break
                    }

                default:
                    throw ExecError.typeMismatch
                }

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

            case .jumpIf:
                guard case let .boolean(b) = stack.last else {
                    throw ExecError.typeMismatch
                }
                if (b) {
                    let offset = code.getInt16(at: ip)
                    ip += 2 + Int(offset)
                } else {
                    ip += 2
                }

            case .jumpIfNot:
                guard case let .boolean(b) = stack.last else {
                    throw ExecError.typeMismatch
                }
                if (!b) {
                    let offset = code.getInt16(at: ip)
                    ip += 2 + Int(offset)
                } else {
                    ip += 2
                }

            case .lookupSymbol:
                let index = code.getUInt16(at: ip)
                guard case let .symbol(s) = code.constants[Int(index)] else {
                    throw ExecError.typeMismatch
                }
                guard let value = lookup(.relative(s), context: context) else {
                    throw ExecError.undefinedSymbol(s)
                }
                stack.append(value)
                ip += 2

            case .lookupMember:
                let index = code.getUInt16(at: ip); ip += 2
                let lhs = stack.removeLast()
                guard case let .symbol(name) = code.constants[Int(index)],
                      let dict = lhs.asValueDictionary else {
                    throw ExecError.typeMismatch
                }
                guard let value = dict[name] else {
                    throw ExecError.undefinedSymbol(name)
                }
                if case let .function(fn) = value {
                    guard case let .entity(entity) = lhs else {
                        throw ExecError.typeMismatch
                    }
                    stack.append(.function(BoundMethod(entity: entity, method: fn)))
                } else {
                    stack.append(value)
                }

            case .assignMember:
                let index = code.getUInt16(at: ip)
                guard case let .symbol(s) = code.constants[Int(index)] else {
                    throw ExecError.typeMismatch
                }
                let rhs = stack.removeLast()
                guard let obj = stack.removeLast().asValueDictionary else {
                    throw ExecError.typeMismatch
                }
                obj[s] = rhs
                ip += 2

            case .subscript:
                guard let index = Int.fromValue(stack.removeLast()) else {
                    throw ExecError.typeMismatch
                }
                guard case let .list(list) = stack.removeLast() else {
                    throw ExecError.typeMismatch
                }
                stack.append(list.values[index])

            case .assignSubscript:
                let rhs = stack.removeLast()
                guard let index = Int.fromValue(stack.removeLast()) else {
                    throw ExecError.typeMismatch
                }
                guard case let .list(list) = stack.removeLast() else {
                    throw ExecError.typeMismatch
                }
                list.values[index] = rhs

            case .makeList:
                let count = Int(code.getUInt16(at: ip))
                let values = Array<Value>(stack[(stack.count - count)..<stack.count])
                stack.removeLast(count)
                stack.append(.list(ValueList(values)))
                ip += 2

            case .makePortal:
                guard case let .entity(destination) = stack.removeLast(),
                      let direction = Direction.fromValue(stack.removeLast()),
                      let portalProto = stack.removeLast().asEntity(Portal.self) else {
                    throw ExecError.typeMismatch
                }
                let portal = portalProto.clone()
                portal.direction = direction
                portal.destination = destination.ref!
                stack.append(.entity(portal))

            case .clone:
                let value = stack.removeLast()
                guard case let .entity(e) = value else {
                    throw ExecError.typeMismatch
                }
                stack.append(.entity(e.clone()))

            case .call:
                let argCount = Int(code.bytecode[ip])
                let args = Array<Value>(stack[(stack.count - argCount)..<stack.count])
                stack.removeLast(argCount)
                guard case let .function(fn) = stack.removeLast() else {
                    throw ExecError.expectedCallable
                }
                guard case let .value(value) = try fn.call(args, context: []) else {
                    // await and fallthrough are not supported results from nested calls.
                    throw ExecError.invalidResult
                }
                stack.append(value)
                ip += 1

            case .stringify:
                let format = Text.Format(rawValue: code.bytecode[ip])
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
                break loop

            case .fallthrough:
                return .fallthrough
            }
        }

        return .value(stack.last ?? .nil)
    }

    private func stringify(value: Value, format: Text.Format) -> String {
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
