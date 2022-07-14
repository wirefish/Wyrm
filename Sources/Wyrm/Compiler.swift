//
//  Compiler.swift
//  Wyrm
//

// MARK: - Opcode

// Bytecode operations. Each operation is one byte followed by 0, 1, or 2 bytes
// describing an optional argument. Two-byte arguments are stored in
// little-endian order.
enum Opcode: UInt8 {
    // Push nil onto the stack.
    case pushNil = 1

    // Push a boolean constant onto the stack.
    case pushTrue, pushFalse

    // The next byte is an integer in the range -128...127. Push it into the stack.
    case pushSmallInt

    // The next two bytes are an index into the constants table. Push the constant
    // at that index onto the stack.
    case pushConstant

    // Pop and discard the value on the top of the stack.
    case pop

    // Pop the top of the stack and create a new local variable.
    case pushLocal

    // The next byte is an unsigned integer. Remove that many locals.
    case popLocals

    // The next byte is the index of a local. Push its value onto the stack.
    case lookupLocal

    // The next byte is the index of a local. Pop the top of the stack and store
    // it in the local.
    case assignLocal

    // Replace the boolean value on the top of the stack with its inverse.
    case not

    // Replace the numeric value on the top of the stack with its negation.
    case negate

    // Replace the reference on the top of the stack with the value it references.
    case deref

    // Replace the two numeric values on the top of the stack with the result of
    // a binary operation.
    case add, subtract, multiply, divide, modulus

    // Replace the two numeric or boolean values on the top of the stack with
    // the result of a comparison.
    case equal, notEqual, less, lessEqual, greater, greaterEqual

    // Change the instruction pointer. The next two bytes are a signed offset.
    case jump

    // Like jump, but only if the value on the top of the stack is true or
    // false, respectively.
    case jumpIf, jumpIfNot

    // Lookup the value of an identifier and push its value onto the stack. The
    // next two bytes are the index of a symbolic constant in the constants
    // table.
    case lookupSymbol

    // Lookup the value of a member of an object. The next two bytes are the
    // index of a symbolic constant; the top of the stack is the object. Pushes
    // the resulting value onto the stack.
    case lookupMember

    // Assign a value to a member of an object. The next two bytes are the index
    // of a symbolic constant. The value to assign is on the top of the stack
    // and the object is next on the stack.
    case assignMember

    // Subscript a list. The top of the stack is the index and the list is next
    // on the stack.
    case `subscript`

    // Assign an element of a list.
    case assignSubscript

    // The next two bytes are the number of values to pop from the stack.
    // Replace them with a value representing a list of those values.
    case makeList

    // Create a Portal from the three values on the top of the stack.
    case makePortal

    // Replace the entity on the top of the stack with a clone.
    case clone

    // Call a function. The top of the stack contains the function and the
    // arguments. The next byte is the number of arguments.
    case call

    // Convert the value at the top of the stack into a string. The following
    // byte describes the desired format.
    case stringify

    // The next byte is the number of strings to pop from the stack. Replace
    // them with their concatenation.
    case joinStrings

    // Await the result of a promise.
    case await

    // Return the value at the top of the stack.
    case `return`

    // Return no value and indicate that control should pass to the next
    // matching event handler.
    case `fallthrough`
}

// MARK: - ScriptFunction extensions

// Methods used to generate bytecode.
extension ScriptFunction {
    func emit(_ op: Opcode) {
        bytecode.append(op.rawValue)
    }

    func emit(_ op: Opcode, _ arg: UInt8) {
        emit(op)
        bytecode.append(arg)
    }

    func emit(_ op: Opcode, _ arg: UInt16) {
        emit(op)
        bytecode.append(UInt8(arg & 0xff))
        bytecode.append(UInt8(arg >> 8))
    }

    func emit(_ op: Opcode, _ arg: Int16) {
        emit(op, UInt16(bitPattern: arg))
    }

    func emitJump(_ op: Opcode) -> Int {
        emit(op, Int16(0))
        return bytecode.count - 2
    }

    func emitJump(_ op: Opcode, to dest: Int) {
        let offset = Int16(dest - (bytecode.count + 3))
        emit(op, offset)
    }

    func patchJump(at pos: Int) {
        let offset = Int16(bytecode.count - (pos + 2))
        bytecode[pos] = UInt8(offset & 0xff)
        bytecode[pos + 1] = (UInt8(offset >> 8))
    }

    func addConstant(_ value: Value) -> UInt16 {
        if let index = constants.firstIndex(of: value) {
            return UInt16(index)
        }
        let index = constants.count
        constants.append(value)
        return UInt16(index)
    }
}

extension ScriptFunction {
    func dump() {
        print("constants:")
        for (i, value) in constants.enumerated() {
            print(String(format: "%5d %@", i, String(describing: value)))
        }

        print("bytecode:")
        var iter = bytecode.makeIterator()
        while let b = iter.next() {
            let op = Opcode(rawValue: b)!
            let opname = String(describing: op).padding(toLength: 12, withPad: " ",
                                                        startingAt: 0)
            switch op {
            case .pushSmallInt, .call:
                let i = Int8(bitPattern: iter.next()!)
                print(String(format: "  %@ %5d", opname, i))
            case .lookupLocal, .assignLocal:
                let i = iter.next()!
                print(String(format: "  %@ %5d", opname, i))
            case .pushConstant, .assignMember, .lookupMember, .lookupSymbol:
                var offset = Int(iter.next()!)
                offset |= Int(iter.next()!) << 8
                print(String(format: "  %@ %5d  ; %@",
                             opname, offset, String(describing: constants[offset])))
            case .makeList:
                var count: UInt16 = UInt16(iter.next()!)
                count |= UInt16(iter.next()!) << 8
                print(String(format: "  %@ %5d", opname, count))
            case .stringify, .joinStrings:
                let i = iter.next()!
                print(String(format: "  %@ %5d", opname, i))
            default:
                print(String(format: "  %@", opname))
            }
        }
    }
}

// MARK: - Compiler

class Compiler {
    // The names of local variables (including parameters) that are currently in scope.
    var locals = [String]()

    // The stack that maintains the number of locals that were defined before
    // the start of each nested scope.
    var scopeLocals = [Int]()

    func compileFunction(parameters: [Parameter], body: ParseNode,
                         in module: Module) -> ScriptFunction? {
        locals = parameters.map(\.name)
        scopeLocals = [locals.count]
        var block = ScriptFunction(module: module, parameters: parameters)
        compile(body, &block)
        return block
    }

    func compile(_ node: ParseNode, _ block: inout ScriptFunction) {
        switch node {
        case let .boolean(b):
            block.emit(b ? .pushTrue : .pushFalse)

        case let .number(n):
            if let i = Int8(exactly: n) {
                block.emit(.pushSmallInt, UInt8(bitPattern: i))
            } else {
                block.emit(.pushConstant, block.addConstant(.number(n)))
            }

        case let .string(text):
            if let s = text.asLiteral {
                 block.emit(.pushConstant, block.addConstant(.string(s)))
            } else {
                block.emit(.pushConstant, block.addConstant(.string(text.prefix)))
                for segment in text.segments {
                    compile(segment.expr, &block)
                    block.emit(.stringify, segment.format.rawValue)
                    block.emit(.pushConstant, block.addConstant(.string(segment.suffix)))
                }
                block.emit(.joinStrings, UInt8(1 + 2 * text.segments.count))
            }

        case let .symbol(s):
            block.emit(.pushConstant, block.addConstant(.symbol(s)))

        case let .identifier(s):
            if let localIndex = locals.lastIndex(of: s) {
                block.emit(.lookupLocal, UInt8(localIndex))
            } else {
                block.emit(.lookupSymbol, block.addConstant(.symbol(s)))
            }

        case let .unaryExpr(op, rhs):
            compile(rhs, &block)
            switch op {
            case .not: block.emit(.not)
            case .minus: block.emit(.negate)
            case .star: block.emit(.deref)
            default:
                break
            }

        case let .binaryExpr(lhs, op, rhs):
            compile(lhs, &block)
            compile(rhs, &block)
            switch op {
            case .plus: block.emit(.add)
            case .minus: block.emit(.subtract)
            case .star: block.emit(.multiply)
            case .slash: block.emit(.divide)
            case .percent: block.emit(.modulus)
            case .less: block.emit(.less)
            case .lessEqual: block.emit(.lessEqual)
            case .greater: block.emit(.greater)
            case .greaterEqual: block.emit(.greaterEqual)
            case .notEqual: block.emit(.notEqual)
            case .equalEqual: block.emit(.equal)
            default: break
            }

        case let .conjuction(lhs, rhs):
            compile(lhs, &block)
            let jump = block.emitJump(.jumpIfNot)
            block.emit(.pop)
            compile(rhs, &block)
            block.patchJump(at: jump)

        case let .disjunction(lhs, rhs):
            compile(lhs, &block)
            let jump = block.emitJump(.jumpIf)
            block.emit(.pop)
            compile(rhs, &block)
            block.patchJump(at: jump)

        case let .list(elements):
            elements.forEach { compile($0, &block) }
            block.emit(.makeList, UInt16(elements.count))

        case let .clone(lhs):
            compile(lhs, &block)
            block.emit(.clone)

        case let .call(fn, args):
            compile(fn, &block)
            args.forEach { compile($0, &block ) }
            block.emit(.call, UInt8(args.count))

        case let .dot(lhs, member):
            compile(lhs, &block)
            block.emit(.lookupMember, block.addConstant(.symbol(member)))

        case let .subscript(lhs, index):
            compile(lhs, &block)
            compile(index, &block)
            block.emit(.subscript)

        case let .exit(portal, direction, destination):
            compile(portal, &block)
            compile(direction, &block)
            compile(destination, &block)
            block.emit(.makePortal)

        case let .var(name, initialValue):
            if locals[scopeLocals.last!...].contains(name) {
                logger.warning("ignoring duplicate declaration of local variable \(name)")
            } else {
                compile(initialValue, &block)
                block.emit(.pushLocal)
                locals.append(name)
            }

        case let .if(predicate, thenBlock, elseBlock):
            compile(predicate, &block)
            let skipThen = block.emitJump(.jumpIfNot)
            block.emit(.pop)
            compileScope(thenBlock, &block)
            if let elseBlock = elseBlock {
                let skipElse = block.emitJump(.jump)
                block.patchJump(at: skipThen)
                compileScope(elseBlock, &block)
                block.patchJump(at: skipElse)
            } else {
                block.patchJump(at: skipThen)
            }

        case let .while(pred, body):
            let start = block.bytecode.count
            compile(pred, &block)
            let endJump = block.emitJump(.jumpIfNot)
            block.emit(.pop)
            compileScope(body, &block)
            block.emitJump(.jump, to: start)
            block.patchJump(at: endJump)
            block.emit(.pop)

        case .for:
            fatalError("for loop not yet implemented")

        case let .await(rhs):
            compile(rhs, &block)
            block.emit(.await)

        case let .return(rhs):
            if let rhs = rhs {
                compile(rhs, &block)
            } else {
                block.emit(.pushNil)
            }
            block.emit(.return)

        case .fallthrough:
            block.emit(.fallthrough)

        case let .block(nodes):
            nodes.forEach { compile($0, &block) }

        case let .assignment(lhs, _, rhs):
            // TODO: += and friends
            switch lhs {
            case let .identifier(s):
                guard let localIndex = locals.lastIndex(of: s) else {
                    fatalError("undefined local \(s)")
                }
                compile(rhs, &block)
                block.emit(.assignLocal, UInt8(localIndex))

            case let .subscript(expr, index):
                compile(expr, &block)
                compile(index, &block)
                compile(rhs, &block)
                block.emit(.assignSubscript)

            case let .dot(expr, member):
                compile(expr, &block)
                compile(rhs, &block)
                block.emit(.assignMember, block.addConstant(.symbol(member)))

            default:
                fatalError("invalid assignment form")
            }

        case let .ignoredValue(expr):
            compile(expr, &block)
            block.emit(.pop)

        case .entity, .quest, .race:
            fatalError("invalid attempt to compile object definition")
        }
    }

    func compileScope(_ scope: ParseNode, _ block: inout ScriptFunction) {
        scopeLocals.append(locals.count)
        compile(scope, &block)
        let prevLocals = scopeLocals.removeLast()
        if locals.count > prevLocals {
            // The block defined some local variables. Pop them from the locals array.
            block.emit(.popLocals, UInt8(locals.count - prevLocals))
            locals.removeLast(locals.count - prevLocals)
        }
    }

    func compile(_ ref: ValueRef, _ block: inout ScriptFunction) {
        switch ref {
        case let .relative(name):
            compile(.identifier(name), &block)
        case let .absolute(module, name):
            compile(.dot(.identifier(module), name), &block)
        }
    }
}
