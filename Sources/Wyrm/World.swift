//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import CoreFoundation
import NIOCore
import NIOPosix

extension Array {
    // Returns the first non-nil value obtained by applying a transform to the
    // elements of the array.
    func firstMap<T>(_ transform: (Element) -> T?) -> T? {
        for value in self {
            if let transformedValue = transform(value) {
                return transformedValue
            }
        }
        return nil
    }
}

class Module: ValueDictionary {
    let name: String
    var bindings = [String:Value]()

    init(_ name: String) {
        self.name = name
    }

    subscript(member: String) -> Value? {
        get { bindings[member] }
        set { bindings[member] = newValue }
    }

    static func == (lhs: Module, rhs: Module) -> Bool {
        return lhs === rhs
    }
}

enum WorldError: Error {
    case invalidModuleSpec(String)
}

enum ValueRef: Equatable, Codable {
    case absolute(String, String)
    case relative(String)
}

class World {
    static var instance: World!

    let rootPath: String
    var modules = [String:Module]()
    let builtins = Module("__BUILTINS__")
    var startableEntities = [Entity]()

    init(rootPath: String) {
        assert(World.instance == nil)

        self.rootPath = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        
        for (name, fn) in ScriptLibrary.functions {
            builtins[name] = .function(NativeFunction(name: name, fn: fn))
        }

        for (name, proto) in [("avatar", Avatar(withPrototype: nil)),
                              ("creature", Creature(withPrototype: nil)),
                              ("entity", Entity(withPrototype: nil)),
                              ("equipment", Equipment(withPrototype: nil)),
                              ("fixture", Fixture(withPrototype: nil)),
                              ("item", Item(withPrototype: nil)),
                              ("location", Location(withPrototype: nil)),
                              ("portal", Portal(withPrototype: nil))] {
            proto.ref = .absolute(builtins.name, name)
            builtins[name] = .entity(proto)
        }

        World.instance = self
    }

    func requireModule(named name: String) -> Module {
        if let module = modules[name] {
            return module
        } else {
            let module = Module(name)
            modules[name] = module
            return module
        }
    }

    func lookup(_ name: String, context: [ValueDictionary]) -> Value? {
        if let value = context.firstMap({ $0[name] }) ?? builtins[name] {
            return value
        } else if let module = modules[name] {
            return .module(module)
        } else {
            return nil
        }
    }

    func lookup(_ ref: ValueRef, in context: Module?) -> Value? {
        switch ref {
        case let .absolute(module, name):
            return modules[module]?.bindings[name]
        case let .relative(name):
            return context?.bindings[name] ?? builtins.bindings[name]
        }
    }
}

// MARK: - starting and stopping

extension World {

    func start() {
        for entity in startableEntities {
            logger.debug("starting \(entity)")
            entity.handleEvent(.when, "start_world", args: [])
        }
    }

    func stop() {
        for entity in startableEntities {
            entity.handleEvent(.when, "stop_world", args: [])
        }
    }
}

// MARK: - loading files

extension World {

    func load() {
        logger.info("loading world from \(rootPath)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for relativePath in try! readModulesFile() {
            let moduleName = moduleName(for: relativePath)
            let module = requireModule(named: moduleName)
            load(contentsOfFile: relativePath, into: module)
        }

        logger.info(String(format: "loaded world in %.3f seconds", CFAbsoluteTimeGetCurrent() - startTime))
    }

    private func readModulesFile() throws -> [String] {
        var files = [String]()

        let text = try String(contentsOfFile: rootPath + "MODULES", encoding: .utf8)

        let lines = text.components(separatedBy: .newlines)
            .map({ $0.prefix(while: { $0 != "#" }) })  // remove comments
            .filter({ !$0.allSatisfy(\.isWhitespace) })  // ignore blank lines

        var currentDir: String?
        for line in lines {
            let indented = line.first!.isWhitespace
            let item = line.trimmingCharacters(in: .whitespaces)
            if item.hasSuffix("/") {
                guard !indented else {
                    throw WorldError.invalidModuleSpec("directory name cannot be indented")
                }
                currentDir = item
            } else if indented {
                guard let dir = currentDir else {
                    throw WorldError.invalidModuleSpec("indented filename has no directory")
                }
                files.append(dir + item + ".wyrm")
            } else {
                currentDir = nil
                files.append(item + ".wyrm")
            }
        }

        return files
    }

    private func load(contentsOfFile relativePath: String, into module: Module) {
        logger.info("loading \(relativePath)")

        let source = try! String(contentsOfFile: rootPath + relativePath, encoding: .utf8)
        let parser = Parser(scanner: Scanner(source))
        for node in parser.parse() {
            switch node {
            case .entity:
                loadEntity(node, into: module)

            case .quest:
                loadQuest(node, into: module)

            default:
                fatalError("unexpected node at top level")
            }
        }
    }

    private func loadEntity(_ node: ParseNode, into module: Module) {
        guard case let .entity(name, prototypeRef, members, handlers, startable) = node else {
            fatalError("invalid call to loadEntity")
        }

        // Find the prototype and construct the new entity.
        guard case let .entity(prototype) = lookup(prototypeRef, in: module) else {
            print("cannot find prototype \(prototypeRef)")
            return
        }
        let entity = prototype.clone()
        entity.ref = .absolute(module.name, name)
        initializeObserver(entity, members: members, handlers: handlers, module: module)
        module.bindings[name] = .entity(entity)

        if startable {
            startableEntities.append(entity)
        }
    }

    private func loadQuest(_ node: ParseNode, into module: Module) {
        guard case let .quest(name, members) = node else {
            fatalError("invalid call to loadQuest")
        }

        let quest = Quest(id: "\(module.name).\(name)")
        let context: [ValueDictionary] = [quest, module]

        // Initialize the members.
        for (name, initialValue) in members {
            if let value = eval(initialValue, context: context) {
                quest[name] = value
            }
        }

        // FIXME: Initialize the phases.

        module.bindings[name] = .quest(quest)
    }

    private func initializeObserver(_ observer: Observer,
                                    members: [ParseNode.Member], handlers: [ParseNode.Handler],
                                    module: Module) {
        let context: [ValueDictionary] = [observer, module]

        // Initialize the members.
        for (name, initialValue) in members {
            if let value = eval(initialValue, context: context) {
                observer[name] = value
            }
        }

        // Compile the event handlers.
        let compiler = Compiler()
        for (phase, name, parameters, body) in handlers {
            let parameters = [Parameter(name: "self", constraint: .none)] + parameters
            if let fn = compiler.compileFunction(parameters: parameters, body: body, in: module) {
                observer.addHandler((phase, name, fn))
            }
        }
    }
    
    private func moduleName(for relativePath: String) -> String {
        if let sep = relativePath.lastIndex(of: "/") {
            return relativePath[..<sep].replacingOccurrences(of: "/", with: "_")
        } else {
            return String(relativePath.prefix(while: { $0 != "." }))
        }
    }
}

// MARK: - evaluating expressions

extension World {

    func eval(_ node: ParseNode, context: [ValueDictionary]) -> Value? {
        switch node {
        case let .boolean(b):
            return .boolean(b)

        case let .number(n):
            return .number(n)

        case let .string(s):
            return .string(s)

        case let .symbol(s):
            return .symbol(s)

        case let .identifier(id):
            return lookup(id, context: context)

        case let .unaryExpr(op, rhs):
            guard let rhs = eval(rhs, context: context) else {
                return nil
            }
            switch op {
            case .minus:
                guard case let .number(n) = rhs else {
                    fatalError("operand to unary - must be a number")
                }
                return .number(-n)
            case .not:
                guard case let .boolean(b) = rhs else {
                    fatalError("operand to ! must be a boolean")
                }
                return .boolean(!b)
            default:
                fatalError("malformed unaryExpr")
            }

        case let .binaryExpr(lhs, op, rhs):
            guard let lhs = eval(lhs, context: context), let rhs = eval(rhs, context: context) else {
                return nil
            }
            switch lhs {
            case let .number(a):
                guard case let .number(b) = rhs else {
                    print("type mismatch in operands of \(op)")
                    break
                }
                switch op {
                case .plus: return .number(a + b)
                case .minus: return .number(a - b)
                case .star: return .number(a * b)
                case .slash: return .number(a / b)
                case .percent: return .number(a.truncatingRemainder(dividingBy: b))
                case .notEqual: return .boolean(a != b)
                case .equalEqual: return .boolean(a == b)
                case .less: return .boolean(a < b)
                case .lessEqual: return .boolean(a <= b)
                case .greater: return .boolean(a > b)
                case .greaterEqual: return .boolean(a >= b)
                default:
                    print("operator \(op) cannot be applied to numeric operands")
                }

            case let .boolean(a):
                guard case let .boolean(b) = rhs else {
                    print("type mismatch in operands of \(op)")
                    break
                }
                switch op {
                case .notEqual: return .boolean(a != b)
                case .equalEqual: return .boolean(a == b)
                default:
                    print("operator \(op) cannot be applied to boolean operands")
                }

            default:
                print("invalid operands of \(op)")
            }

        case let .conjuction(lhs, rhs):
            guard let lhs = eval(lhs, context: context) else {
                return nil
            }
            guard case let .boolean(a) = lhs else {
                print("expression before && does not evaluate to a boolean value")
                return nil
            }
            if !a {
                return .boolean(false)
            } else {
                guard let rhs = eval(rhs, context: context) else {
                    return nil
                }
                guard case let .boolean(b) = rhs else {
                    print("expression after && does not evaluate to a boolean value")
                    return nil
                }
                return .boolean(b)
            }

        case let .disjunction(lhs, rhs):
            guard let lhs = eval(lhs, context: context) else {
                return nil
            }
            guard case let .boolean(a) = lhs else {
                print("expression before || does not evaluate to a boolean value")
                return nil
            }
            if a {
                return .boolean(true)
            } else {
                guard let rhs = eval(rhs, context: context) else {
                    return nil
                }
                guard case let .boolean(b) = rhs else {
                    print("expression after || does not evaluate to a boolean value")
                    return nil
                }
                return .boolean(b)
            }

        case let .list(nodes):
            let values = nodes.map { eval($0, context: context) }
            guard values.allSatisfy({ $0 != nil}) else {
                break
            }
            return .list(ValueList(values.map({ $0! })))

        case let .exit(portal, dir, dest):
            guard let portal = eval(portal, context: context) else {
                break
            }
            guard case let .entity(portalPrototype) = portal,
                  let portalPrototype = portalPrototype as? Portal else {
                print("invalid exit portal")
                break
            }
            guard let destRef = dest.asValueRef else {
                print("exit destination must be a reference")
                break
            }
            return .exit(Exit(portal: portalPrototype.clone(), direction: dir, destination: destRef))

        case let .clone(lhs):
            guard let lhs = eval(lhs, context: context) else {
                break
            }
            guard case let .entity(entity) = lhs else {
                print("cannot clone non-entity")
                break
            }
            return .entity(entity.clone())

        case let .call(lhs, args):
            guard let lhs = eval(lhs, context: context) else {
                break
            }
            let args = args.map { eval($0, context: context) }
            guard args.allSatisfy({ $0 != nil}) else {
                break
            }
            guard case let .function(fn) = lhs else {
                print("expression is not callable")
                break
            }
            return try! fn.call(args.map({ $0! }), context: [])

        case let .dot(lhs, member):
            guard let lhs = eval(lhs, context: context) else {
                break
            }
            guard let lhs = lhs.asValueDictionary else {
                print("cannot apply . operator to operand")
                break
            }
            return lhs[member]

        case let .subscript(lhs, rhs):
            guard let lhs = eval(lhs, context: context),
                  let rhs = eval(rhs, context: context) else {
                break
            }
            guard case let .list(lhs) = lhs else {
                print("cannot apply [] operator to non-list")
                break
            }
            guard let index = Int(fromValue: rhs) else {
                print("subscript index must be an integer")
                break
            }
            return lhs.values[index]

        default:
            fatalError("not an expression: \(node)")
        }

        return nil
    }
}

// MARK: - executing compiled functions

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
                guard let index = Int(fromValue: stack.removeLast()) else {
                    throw ExecError.typeMismatch
                }
                guard case let .list(list) = stack.removeLast() else {
                    throw ExecError.typeMismatch
                }
                stack.append(list.values[index])

            case .assignSubscript:
                let rhs = stack.removeLast()
                guard let index = Int.init(fromValue: stack.removeLast()) else {
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
                      let direction = Direction(fromValue: stack.removeLast()),
                      case let .entity(portal) = stack.removeLast(),
                      let portal = portal as? Portal else {
                    throw ExecError.typeMismatch
                }
                stack.append(.exit(Exit(portal: portal.clone(), direction: direction,
                                        destination: destination.ref!)))

            case .call:
                let argCount = Int(code.bytecode[ip])
                let args = Array<Value>(stack[(stack.count - argCount)..<stack.count])
                stack.removeLast(argCount)
                guard case let .function(fn) = stack.removeLast() else {
                    throw ExecError.expectedCallable
                }
                stack.append(try fn.call(args, context: []) ?? .nil)
                ip += 1

            case .return:
                break loop

            default:
                fatalError("instruction \(op) not implemented")
            }
        }

        return stack.last ?? .nil
    }
}
