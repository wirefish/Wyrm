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

enum ValueRef: Hashable, Codable, CustomStringConvertible {
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
        try c.encode(description)
    }

    var description: String {
        switch self {
        case let .absolute(module, name):
            return "\(module).\(name)"
        case let .relative(name):
            return name
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

        let scriptProviders: [ScriptProvider.Type] = [
            ScriptLibrary.self,
            QuestScriptFunctions.self,
        ]

        for provider in scriptProviders {
            for (name, fn) in provider.functions {
                builtins[name] = .function(NativeFunction(name: name, fn: fn))
            }
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

        guard let av = lookup(config.world.avatarPrototype, context: nil)?.asEntity(Avatar.self) else {
            throw WorldError.invalidAvatarPrototype
        }
        avatarPrototype = av

        guard let loc = lookup(config.world.startLocation, context: nil)?.asEntity(Location.self) else {
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

    func lookup(_ ref: ValueRef, context: [ValueDictionary]) -> Value? {
        switch ref {
        case let .absolute(module, name):
            return modules[module]?[name]
        case let .relative(name):
            if let value = context.firstMap({ $0[name] }) ?? builtins[name] {
                return value
            } else if let module = modules[name] {
                return .module(module)
            } else {
                return nil
            }
        }
    }

    func lookup(_ ref: ValueRef, context: ValueDictionary?) -> Value? {
        switch ref {
        case let .absolute(module, name):
            return modules[module]?[name]
        case let .relative(name):
            return context?[name] ?? builtins[name]
        }
    }

    func lookup(_ ref: ValueRef, context: ValueRef) -> Value? {
        switch ref {
        case let .absolute(module, name):
            return modules[module]?.bindings[name]
        case let .relative(name):
            guard case let .absolute(module, _) = context else {
                return nil
            }
            return modules[module]?.bindings[name]
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

        twinPortals()

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
        guard case let .entity(prototype) = lookup(prototypeRef, context: module) else {
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
            do {
                quest[name] = try eval(initialValue, context: context)
            } catch {
                print("\(quest.ref) \(name): \(error)")
            }
        }

        for (phaseName, members) in phases {
            let phase = QuestPhase(phaseName)
            for (name, initialValue) in members {
                do {
                    phase[name] = try eval(initialValue, context: context)
                } catch {
                    print("\(quest.ref) \(phaseName) \(name): \(error)")
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
            do {
                entity[name] = try eval(initialValue, context: context)
            } catch {
                print("\(entity.ref!) \(name) \(error)")
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

    private func twinPortals() {
        for entity in startableEntities {
            guard let location = entity as? Location else {
                continue
            }
            for portal in location.exits {
                guard portal.twin == nil else {
                    continue
                }
                guard let destinationRef = portal.destination else {
                    logger.warning("portal \(portal.direction) from \(location.ref!) has no destination")
                    continue
                }
                guard let destination = lookup(destinationRef, context: location.ref!)?.asEntity(Location.self) else {
                    logger.warning("portal \(portal.direction) from \(location.ref!) has invalid destination \(destinationRef)")
                    continue
                }
                guard let twin = destination.findExit(portal.direction.opposite) else {
                    logger.warning("cannot find twin for portal \(portal.direction) from \(location.ref!)")
                    continue
                }
                guard twin.destination != nil else {
                    logger.warning("twin of portal \(portal.direction) from \(location.ref!) has no destination")
                    continue
                }
                guard lookup(twin.destination!, context: destination.ref!)?.asEntity(Location.self) == location else {
                    logger.warning("twin of portal \(portal.direction) from \(location.ref!) has mismatched destination \(twin.destination!)")
                    continue
                }
                portal.twin = twin
                twin.twin = portal
            }
        }
    }
}

// MARK: - evaluating expressions

enum EvalError: Error {
    case typeMismatch(String)
    case undefinedIdentifier(String)
    case malformedExpression
    case invalidResult
}

extension World {

    func eval(_ node: ParseNode, context: [ValueDictionary]) throws -> Value {
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
            guard let value = lookup(.relative(id), context: context) else {
                throw EvalError.undefinedIdentifier(id)
            }
            return value

        case let .unaryExpr(op, rhs):
            let rhs = try eval(rhs, context: context)
            switch op {
            case .minus:
                guard case let .number(n) = rhs else {
                    throw EvalError.typeMismatch("operand of '-' must be a number")
                }
                return .number(-n)
            case .not:
                guard case let .boolean(b) = rhs else {
                    throw EvalError.typeMismatch("operand of '!' must be a boolean")
                }
                return .boolean(!b)
            default:
                throw EvalError.malformedExpression
            }

        case let .binaryExpr(lhs, op, rhs):
            let lhs = try eval(lhs, context: context)
            let rhs = try eval(rhs, context: context)
            switch lhs {
            case let .number(a):
                guard case let .number(b) = rhs else {
                    throw EvalError.typeMismatch("operands of '\(op)' must be of same type")
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
                    throw EvalError.typeMismatch("operator \(op) cannot be applied to numbers")
                }

            case let .boolean(a):
                guard case let .boolean(b) = rhs else {
                    throw EvalError.typeMismatch("operands of '\(op)' must be of same type")
                }
                switch op {
                case .notEqual: return .boolean(a != b)
                case .equalEqual: return .boolean(a == b)
                default:
                    throw EvalError.typeMismatch("operator \(op) cannot be applied to booleans")
                }

            default:
                throw EvalError.typeMismatch("invalid operaands of \(op)")
            }

        case let .conjuction(lhs, rhs):
            let lhs = try eval(lhs, context: context)
            guard case let .boolean(a) = lhs else {
                throw EvalError.typeMismatch("expression before && must be a boolean")
            }
            if !a {
                return .boolean(false)
            } else {
                let rhs = try eval(rhs, context: context)
                guard case let .boolean(b) = rhs else {
                    throw EvalError.typeMismatch("expression after && must be a boolean")
                }
                return .boolean(b)
            }

        case let .disjunction(lhs, rhs):
            let lhs = try eval(lhs, context: context)
            guard case let .boolean(a) = lhs else {
                throw EvalError.typeMismatch("expression before || must be a boolean")
            }
            if a {
                return .boolean(true)
            } else {
                let rhs = try eval(rhs, context: context)
                guard case let .boolean(b) = rhs else {
                    throw EvalError.typeMismatch("expression after || must be a boolean")
                }
                return .boolean(b)
            }

        case let .list(nodes):
            let values = try nodes.map { try eval($0, context: context) }
            return .list(ValueList(values))

        case let .exit(portalRef, direction, destination):
            guard let portalProto = lookup(portalRef, context: context)?.asEntity(Portal.self) else {
                throw EvalError.typeMismatch("invalid exit portal")
            }
            let portal = portalProto.clone()
            portal.direction = direction
            portal.destination = destination
            return .entity(portal)

        case let .clone(lhs):
            let lhs = try eval(lhs, context: context)
            guard case let .entity(entity) = lhs else {
                throw EvalError.typeMismatch("cannot clone non-entity")
            }
            return .entity(entity.clone())

        case let .call(lhs, args):
            let lhs = try eval(lhs, context: context)
            let args = try args.map { try eval($0, context: context) }
            guard case let .function(fn) = lhs else {
                throw EvalError.typeMismatch("expression is not callable")
            }
            guard case let .value(value) = try fn.call(args, context: []) else {
                throw EvalError.invalidResult
            }
            return value

        case let .dot(lhs, member):
            let lhs = try eval(lhs, context: context)
            guard let lhs = lhs.asValueDictionary else {
                throw EvalError.typeMismatch("cannot apply . to non-object")
            }
            return lhs[member] ?? .nil

        case let .subscript(lhs, rhs):
            let lhs = try eval(lhs, context: context)
            let rhs = try eval(rhs, context: context)
            guard case let .list(lhs) = lhs else {
                throw EvalError.typeMismatch("cannot apply [] to non-list")
            }
            guard let index = Int.fromValue(rhs) else {
                throw EvalError.typeMismatch("subscript index must be an integer")
            }
            return lhs.values[index]

        default:
            throw EvalError.malformedExpression
        }
    }
}
