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
    case add, subtract, multiply, divide
    case equal, notEqual, less, lessEqual, greater, greaterEqual

    // Change the instruction offset.
    case jump, jumpIfFalse

    // Resolve a reference on the top of the stack.
    case lookup

    // Pop the value on top of the stack and store it in a member of the enclosing entity.
    case assignMember
}

class CodeBlock {
    var locals = [Value]()
    var constants = [Value]()
    var bytecode = [UInt8]()

    func emit(_ op: Opcode) {
        bytecode.append(op.rawValue)
    }

    func emit(_ op: Opcode, _ arg: UInt8) {
        emit(op)
        bytecode.append(arg)
    }

    func emit(_ op: Opcode, _ offset: UInt16) {
        emit(op)
        bytecode.append(UInt8(offset & 0xff))
        bytecode.append(UInt8(offset >> 8))
    }

    func addConstant(_ value: Value) -> UInt16 {
        let n = constants.count
        constants.append(value)
        return UInt16(n)
    }

    func dump() {
        print(constants)
        var iter = bytecode.makeIterator()
        while let b = iter.next() {
            let op = Opcode(rawValue: b)!
            switch op {
            case .pushSmallInt:
                let i = Int8(bitPattern: iter.next()!)
                print(op, i)
            case .pushConstant, .assignMember:
                var offset: UInt16 = UInt16(iter.next()!)
                offset |= UInt16(iter.next()!) << 8
                print(op, offset)
            default:
                print(op)
            }
        }
    }
}

class Compiler {
    func compile(_ node: ParseNode, _ block: inout CodeBlock) {
        switch node {

        case .literal(let token):
            switch token {
            case .boolean(let b):
                block.emit(b ? .pushTrue : .pushFalse)
            case .number(let n):
                if let i = Int8(exactly: n) {
                    block.emit(.pushSmallInt, UInt8(bitPattern: i))
                } else {
                    block.emit(.pushConstant, block.addConstant(.number(n)))
                }
            case .symbol(let s):
                block.emit(.pushConstant, block.addConstant(.symbol(s)))
            case .string(let s):
                block.emit(.pushConstant, block.addConstant(.string(s)))
            default:
                break
            }

        case .identifier(let s):
            block.emit(.pushConstant, block.addConstant(.symbol(s)))
            block.emit(.lookup)

        case .unaryExpr(let op, let rhs):
            compile(rhs, &block)
            switch op {
            case .not:
                block.emit(.not)
            case .minus:
                block.emit(.negate)
            default:
                break
            }

/*

        case .binaryExpr(_, _, _):
            <#code#>
        case .list(_):
            <#code#>
        case .call(_, _):
            <#code#>
        case .dot(_, _):
            <#code#>
        case .subscript(_, _):
            <#code#>
        case .var(_, _):
            <#code#>
        case .if(_, _, _):
            <#code#>
        case .for(_, _, _):
            <#code#>
        case .block(_):
            <#code#>
        case .initializer(_, _):
            <#code#>
        case .handler(_, _, _):
            <#code#>
        case .member(name: let name, value: let value):
            <#code#>

*/

        case .entity(name: let name, prototype: let prototype, members: let members,
                     initializer: let initializer, handlers: let handlers):
            for member in members {
                guard case let .member(name, initializer) = member else {
                    break
                }
                compile(initializer, &block)
                block.emit(.assignMember, block.addConstant(.symbol(name)))
            }

        default:
            break
        }
    }
}
