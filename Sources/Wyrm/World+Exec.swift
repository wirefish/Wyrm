//
//  World+Exec.swift
//  Wyrm
//

enum ExecError: Error {
    case typeMismatch
    case undefinedSymbol(String)
    case expectedCallable
}

extension ScriptFunction {
    func getUInt16(at offset: Int) -> UInt16 {
        UInt16(bytecode[offset]) | (UInt16(bytecode[offset + 1]) << 8)
    }
}

extension World {
    func exec(_ code: ScriptFunction, args: [Value], context: [ValueDictionary]) throws -> Value {
        // The arguments are always the first locals, and self is always the first argument.
        // Subsequent locals start with no value.
        var locals = args
        locals += Array<Value>(repeating: .nil, count: code.locals.count - args.count)

        var stack = [Value]()
        var ip = 0
        loop: while ip < code.bytecode.count {
            let op = Opcode(rawValue: code.bytecode[ip])!
            ip += 1
            switch op {

            case .pushTrue: stack.append(.boolean(true))

            case .pushFalse: stack.append(.boolean(false))

            case .pushSmallInt:
                let v = Int8(bitPattern: code.bytecode[ip])
                stack.append(.number(Double(v)))
                ip += 1

            case .pushConstant:
                let index = UInt16(code.bytecode[ip]) | (UInt16(code.bytecode[ip + 1]) << 8)
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
                let offset = UInt16(code.bytecode[ip]) | (UInt16(code.bytecode[ip + 1]) << 8)
                ip += 2 + Int(offset)

            case .jumpIf:
                guard case let .boolean(b) = stack.last else {
                    throw ExecError.typeMismatch
                }
                if (b) {
                    let offset = UInt16(code.bytecode[ip]) | (UInt16(code.bytecode[ip + 1]) << 8)
                    ip += 2 + Int(offset)
                } else {
                    ip += 2
                }

            case .jumpIfNot:
                guard case let .boolean(b) = stack.last else {
                    throw ExecError.typeMismatch
                }
                if (!b) {
                    let offset = UInt16(code.bytecode[ip]) | (UInt16(code.bytecode[ip + 1]) << 8)
                    ip += 2 + Int(offset)
                } else {
                    ip += 2
                }

            case .lookupSymbol:
                let index = code.getUInt16(at: ip)
                guard case let .symbol(s) = code.constants[Int(index)] else {
                    throw ExecError.typeMismatch
                }
                guard let value = lookup(s, context: context) else {
                    throw ExecError.undefinedSymbol(s)
                }
                stack.append(value)
                ip += 2

            case .lookupMember:
                fatalError("lookupMember not yet implemented")

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

            case .makeExit:
                guard case let .entity(destination) = stack.removeLast(),
                      let direction = Direction.fromValue(stack.removeLast()),
                      case let .entity(portal) = stack.removeLast(),
                      let portal = portal as? Portal else {
                    throw ExecError.typeMismatch
                }
                stack.append(.exit(Exit(portal: portal.clone(), direction: direction,
                                        destination: destination.ref!)))

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
                stack.append(try fn.call(args, context: []) ?? .nil)
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
                fatalError("await not yet implemented")

            case .return:
                break loop

            case .fallthrough:
                fatalError("fallthrough not yet implemented")
            }
        }

        return stack.last ?? .nil
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
        default:
            return String(describing: value)
        }
    }
}
