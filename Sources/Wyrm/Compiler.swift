//
//  Compiler.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

enum Opcode: UInt8 {
    case nop = 0

    // Manipulate the value stack.
    case pushNil
    case pushTrue
    case pushFalse
    case pushSmallInt  // next byte is signed value -128...127
    case pushConstant  // next two bytes are offset into constants table
    case pop

    // Transform the top of the value stack with a unary operation.
    case not, negate

    // Replace the top two values on the stack with the result of a binary operation.
    case add, subtract, multiply, divide, modulus
    case equal, notEqual, less, lessEqual, greater, greaterEqual

    // Change the instruction offset.
    case jump, jumpIfFalse

    // Resolve a reference on the top of the stack.
    case lookup

    // Pop the value on top of the stack and store it in a member of the enclosing entity.
    case assignMember

    // Lookup a member of an object.
    case lookupMember

    // Subscript a list.
    case `subscript`

    // The next two bytes are the number of values to pop from the stack. Replace them with
    // a value representing a list of those values.
    case makeList

    // Create an exit from the three values on the top of the stack.
    case makeExit

    // Call a function. The top of the stack contains the function and the arguments.
    // The next byte is the number of arguments.
    case call
}

class CodeBlock {
    var locals = [String]()
    var constants = [Value]()
    var bytecode = [UInt8]()

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

    func addConstant(_ value: Value) -> UInt16 {
        let n = constants.count
        constants.append(value)
        return UInt16(n)
    }

    func dump() {
        print("constants:")
        for (i, value) in constants.enumerated() {
            print(String(format: "%5d %@", i, String(describing: value)))
        }

        print("locals:")
        for (i, name) in locals.enumerated() {
            print(String(format: "%5d %@", i, name))
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
            case .pushConstant, .assignMember, .lookupMember:
                var offset = Int(iter.next()!)
                offset |= Int(iter.next()!) << 8
                print(String(format: "  %@ %5d  ; %@",
                             opname, offset, String(describing: constants[offset])))
            case .makeList:
                var count: UInt16 = UInt16(iter.next()!)
                count |= UInt16(iter.next()!) << 8
                print(String(format: "  %@ %5d", opname, count))
            default:
                print(String(format: "  %@", opname))
            }
        }
    }
}

class Compiler {
    func compile(_ node: ParseNode, _ block: inout CodeBlock) {
        switch node {
        case let .boolean(b):
            block.emit(b ? .pushTrue : .pushFalse)

        case let .number(n):
            if let i = Int8(exactly: n) {
                block.emit(.pushSmallInt, UInt8(bitPattern: i))
            } else {
                block.emit(.pushConstant, block.addConstant(.number(n)))
            }

        case let .symbol(s):
            block.emit(.pushConstant, block.addConstant(.symbol(s)))

        case let .string(s):
            block.emit(.pushConstant, block.addConstant(.string(s)))

        case let .identifier(s):
            block.emit(.pushConstant, block.addConstant(.symbol(s)))
            block.emit(.lookup)

        case let .unaryExpr(op, rhs):
            compile(rhs, &block)
            switch op {
            case .not:
                block.emit(.not)
            case .minus:
                block.emit(.negate)
            default:
                break
            }

        case let .binaryExpr(lhs, op, rhs):
            compile(lhs, &block)
            compile(rhs, &block)
            switch op {
            case .plus:
                block.emit(.add)
            case .minus:
                block.emit(.subtract)
            case .star:
                block.emit(.multiply)
            case .slash:
                block.emit(.divide)
            case .percent:
                block.emit(.modulus)
            default:
                break
            }

        case let .list(elements):
            elements.forEach { compile($0, &block) }
            block.emit(.makeList, UInt16(elements.count))

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

/*
        case .var(_, _):
            <#code#>
        case .if(_, _, _):
            <#code#>
        case .for(_, _, _):
            <#code#>

*/
        case let .block(nodes):
            nodes.forEach { compile($0, &block) }

        case let .exit(portal, direction, destination):
            compile(portal, &block)
            block.emit(.pushConstant, block.addConstant(direction.toValue()))
            compile(destination, &block)
            block.emit(.makeExit)

        case .entity:
            fatalError("invalid attempt to compile entity definition")
            
        default:
            break
        }
    }
}
