//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import CoreFoundation

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
}

enum ValueRef: Hashable, Codable {
    case absolute(String, String)
    case relative(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        if let sep = s.firstIndex(of: ".") {
            self = .absolute(String(s.prefix(upTo: sep)), String(s.suffix(after: sep)))
        } else {
            self = .relative(s)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .absolute(module, name):
            try c.encode("\(module).\(name)")
        case let .relative(name):
            try c.encode(name)
        }
    }
}

enum WorldError: Error {
    case invalidModuleSpec(String)
    case cannotOpenDatabase
    case invalidAvatarPrototype
    case invalidStartLocation
}

class World {
    static var instance: World!

    let rootPath: String
    var modules = [String:Module]()
    let builtins = Module("__BUILTINS__")
    var startableEntities = [Entity]()
    let db = Database()
    var avatarPrototype: Avatar!
    var startLocation: Location!

    init(config: Config) throws {
        assert(World.instance == nil)

        guard db.open(config.world.databasePath) else {
            throw WorldError.cannotOpenDatabase
        }

        let rootPath = config.world.rootPath
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

        try load()

        guard let av = lookup(config.world.avatarPrototype, in: nil)?.asEntity(Avatar.self) else {
            throw WorldError.invalidAvatarPrototype
        }
        avatarPrototype = av

        guard let loc = lookup(config.world.startLocation, in: nil)?.asEntity(Location.self) else {
            throw WorldError.invalidStartLocation
        }
        startLocation = loc

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

    func load() throws {
        logger.info("loading world from \(rootPath)")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for relativePath in try readModulesFile() {
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
        guard let defs = parser.parse() else {
            return
        }
        for def in defs {
            switch def {
            case .entity:
                loadEntity(def, into: module)

            case .quest:
                loadQuest(def, into: module)

            default:
                fatalError("unexpected definition at top level")
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
        initializeEntity(entity, members: members, handlers: handlers, module: module)
        module.bindings[name] = .entity(entity)

        if startable {
            startableEntities.append(entity)
        }
    }

    private func loadQuest(_ node: ParseNode, into module: Module) {
        guard case let .quest(name, members, phases) = node else {
            fatalError("invalid call to loadQuest")
        }

        let quest = Quest(ref: .absolute(module.name, name))
        let context: [ValueDictionary] = [quest, module]

        // Initialize the members.
        for (name, initialValue) in members {
            if let value = eval(initialValue, context: context) {
                quest[name] = value
            }
        }

        for (phaseName, members) in phases {
            let phase = QuestPhase(phaseName)
            for (name, initialValue) in members {
                if let value = eval(initialValue, context: context) {
                    phase[name] = value
                }
            }
            quest.phases.append(phase)
        }

        module.bindings[name] = .quest(quest)
    }

    private func initializeEntity(_ entity: Entity,
                                  members: [ParseNode.Member], handlers: [ParseNode.Handler],
                                  module: Module) {
        let context: [ValueDictionary] = [entity, module]

        // Initialize the members.
        for (name, initialValue) in members {
            if let value = eval(initialValue, context: context) {
                entity[name] = value
            }
        }

        // Compile the event handlers.
        let compiler = Compiler()
        for (phase, event, parameters, body) in handlers {
            let parameters = [Parameter(name: "self", constraint: .none)] + parameters
            if let fn = compiler.compileFunction(parameters: parameters, body: body, in: module) {
                entity.handlers.append(EventHandler(phase: phase, event: event, fn: fn))
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

        case let .string(text):
            guard let s = text.asLiteral else {
                fatalError("interpolated string not allowed in this context")
            }
            return .string(s)

        case let .symbol(s):
            return .symbol(s)

        case let .identifier(id):
            guard let value = lookup(id, context: context) else {
                // FIXME: need to propogate errors here
                logger.error("cannot lookup identifier \(id)")
                return nil
            }
            return value

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
            guard let index = Int.fromValue(rhs) else {
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
