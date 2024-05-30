//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import CoreFoundation
import Dispatch
import Network
import XCTest

class Module: ValueDictionary {
  let name: String
  var bindings = [String:Value]()
  var region: Region?

  init(_ name: String) {
    self.name = name
  }

  func get(_ member: String) -> Value? {
    return bindings[member]
  }

  func set(_ member: String, to value: Value) {
    bindings[member] = value
  }
}

enum Ref: Hashable, Codable, CustomStringConvertible, ValueRepresentable {
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

  static func fromValue(_ value: Value) -> Ref? {
    guard case let .ref(ref) = value else {
      return nil
    }
    return ref
  }

  func toValue() -> Value {
    return .ref(self)
  }

  func deref() -> Value? {
    World.instance.lookup(self, context: nil)
  }

  func toAbsolute(in module: Module) -> Ref {
    switch self {
    case .absolute:
      return self
    case let .relative(name):
      return .absolute(module.name, name)
    }
  }
}

struct Extension {
  let ref: Ref
  var handlers = [EventHandler]()
  var methods = [String:Value]()
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
  var locations = [Location]()
  var extensions = [Extension]()
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
      builtins.set(name, to: .function(NativeFunction(fn: fn)))
    }

    for (name, proto) in [("avatar", Avatar()),
                          ("container", Container()),
                          ("creature", Creature()),
                          ("entity", Entity()),
                          ("equipment", Equipment()),
                          ("fixture", PhysicalEntity()),
                          ("item", Item()),
                          ("location", Location()),
                          ("portal", Portal()),
                          ("weapon", Weapon())] {
      proto.ref = .absolute(builtins.name, name)
      builtins.set(name, to: .entity(proto))
    }

    World.instance = self
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

  func lookup(_ ref: Ref, context: [ValueDictionary]) -> Value? {
    switch ref {
    case let .absolute(module, name):
      return modules[module]?.get(name)
    case let .relative(name):
      if let value = context.firstMap({ $0.get(name) }) ?? builtins.get(name) {
        return value
      } else if let module = modules[name] {
        return .module(module)
      } else {
        return nil
      }
    }
  }

  func lookup(_ ref: Ref, context: ValueDictionary? = nil) -> Value? {
    switch ref {
    case let .absolute(module, name):
      return modules[module]?.get(name)
    case let .relative(name):
      return context?.get(name) ?? builtins.get(name)
    }
  }

  func lookup(_ ref: Ref, context: Ref) -> Value? {
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

// MARK: - starting the world

extension World {
  func start() {
    logger.info("starting \(locations.count) locations")
    for location in locations {
      location.handleEvent(.when, "startWorld", args: [])
      for entity in location.contents {
        entity.location = location
        entity.handleEvent(.when, "startWorld", args: [])
      }
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

    applyExtensions()

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

      case .race:
        loadRace(def, into: module)

      case .skill:
        loadSkill(def, into: module)

      case .region:
        loadRegion(def, into: module)

      case .extension:
        loadExtension(def, into: module)
      }
    }
  }

  private func loadEntity(_ node: Definition, into module: Module) {
    guard case let .entity(name, prototypeRef, members, handlers, methods, isLocation) = node else {
      fatalError("invalid call to loadEntity")
    }

    // Find the prototype and construct the new entity.
    guard case let .entity(prototype) = lookup(prototypeRef, context: module) else {
      print("cannot find prototype \(prototypeRef)")
      return
    }
    let entity = prototype.clone()
    entity.ref = .absolute(module.name, name)

    // Initialize the members.
    for (name, initialValue) in members {
      do {
        try entity.set(name, to: try evalInitializer(initialValue, in: module))
      } catch {
        logger.error("\(entity.ref!) \(name) \(error)")
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

    // Compile the methods.
    for (name, parameters, body) in methods {
      let parameters = [Parameter(name: "self", constraint: .none)] + parameters
      if let fn = compiler.compileFunction(parameters: parameters, body: body, in: module) {
        entity.extraMembers[name] = .function(fn)
      }
    }

    module.bindings[name] = .entity(entity)
    if isLocation {
      let location = entity as! Location
      location.region = module.region
      locations.append(location)
    }
  }

  private func loadQuest(_ node: Definition, into module: Module) {
    guard case let .quest(name, members, phases) = node else {
      fatalError("invalid call to loadQuest")
    }

    let quest = Quest(ref: .absolute(module.name, name))

    // Initialize the members.
    for (name, initialValue) in members {
      do {
        try quest.set(name, to: try evalInitializer(initialValue, in: module))
      } catch {
        logger.error("\(quest.ref) \(name): \(error)")
      }
    }

    for (phaseName, members) in phases {
      let phase = QuestPhase(phaseName)
      for (name, initialValue) in members {
        do {
          try phase.set(name, to: try evalInitializer(initialValue, in: module))
        } catch {
          logger.error("\(quest.ref) \(phaseName) \(name): \(error)")
        }
      }
      quest.phases.append(phase)
    }

    module.bindings[name] = .quest(quest)
  }

  private func loadRace(_ node: Definition, into module: Module) {
    guard case let .race(name, members) = node else {
      fatalError("invalid call to loadRace")
    }

    let race = Race(ref: .absolute(module.name, name))

    for (name, initialValue) in members {
      do {
        try race.set(name, to: try evalInitializer(initialValue, in: module))
      } catch {
        logger.error("\(race.ref) \(name): \(error)")
      }
    }

    module.bindings[name] = .race(race)
  }

  private func loadSkill(_ node: Definition, into module: Module) {
    guard case let .skill(name, members) = node else {
      fatalError("invalid call to loadSkill")
    }

    let skill = Skill(ref: .absolute(module.name, name))

    for (name, initialValue) in members {
      do {
        try skill.set(name, to: try evalInitializer(initialValue, in: module))
      } catch {
        logger.error("\(skill.ref) \(name): \(error)")
      }
    }

    module.bindings[name] = .skill(skill)
  }

  private func loadRegion(_ node: Definition, into module: Module) {
    guard case let .region(members) = node else {
      fatalError("invalid call to loadRegion")
    }

    let region = Region()

    // Initialize the members.
    for (name, initialValue) in members {
      do {
        try region.set(name, to: try evalInitializer(initialValue, in: module))
      } catch {
        logger.error("defregion \(module.name): \(error)")
      }
    }

    if module.region == nil {
      module.region = region
    } else {
      logger.warning("ignoring duplicate region definition in module \(module.name)")
    }
  }

  private func loadExtension(_ node: Definition, into module: Module) {
    guard case let .extension(ref, handlers, methods) = node else {
      fatalError("invalid call to loadExtension")
    }

    var ext = Extension(ref: ref.toAbsolute(in: module))

    // Compile the event handlers.
    let compiler = Compiler()
    for (phase, event, parameters, body) in handlers {
      let parameters = [Parameter(name: "self", constraint: .none)] + parameters
      if let fn = compiler.compileFunction(parameters: parameters, body: body, in: module) {
        ext.handlers.append(EventHandler(phase: phase, event: event, fn: fn))
      }
    }

    // Compile the methods.
    for (name, parameters, body) in methods {
      let parameters = [Parameter(name: "self", constraint: .none)] + parameters
      if let fn = compiler.compileFunction(parameters: parameters, body: body, in: module) {
        ext.methods[name] = .function(fn)
      }
    }

    extensions.append(ext)
  }

  private func moduleName(for relativePath: String) -> String {
    if let sep = relativePath.lastIndex(of: "/") {
      return relativePath[..<sep].replacingOccurrences(of: "/", with: "_")
    } else {
      return String(relativePath.prefix(while: { $0 != "." }))
    }
  }

  private func applyExtensions() {
    for ext in extensions {
      guard case let .entity(entity) = lookup(ext.ref) else {
        logger.warning("cannot apply extension to undefined entity \(ext.ref)")
        continue
      }
      entity.handlers = ext.handlers + entity.handlers
      entity.extraMembers.merge(ext.methods) { (old, new) -> Value in
        logger.warning("extension cannot replace existing method")
        return old
      }
    }
    extensions.removeAll()
  }

  private func twinPortals() {
    for location in locations {
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

// MARK: - evaluating member initializers

enum EvalError: Error {
  case typeMismatch(String)
  case invalidExpression(String)
}

extension World {
  func evalInitializer(_ node: Expression, in module: Module) throws -> Value {
    switch node {
    case .nil:
      return .nil

    case let .boolean(b):
      return .boolean(b)

    case let .number(n):
      return .number(n)

    case let .string(text):
      guard let s = text.asLiteral else {
        throw EvalError.invalidExpression("interpolated string not allowed in member initializer")
      }
      return .string(s)

    case let .symbol(s):
      return .symbol(s)

    case let .identifier(id):
      return .ref(.absolute(module.name, id))

    case let .unaryExpr(op, rhs):
      let rhs = try evalInitializer(rhs, in: module)
      switch op {
      case .minus:
        guard case let .number(n) = rhs else {
          throw EvalError.typeMismatch("operand of unary - must be a number")
        }
        return .number(-n)
      case .not:
        guard case let .boolean(b) = rhs else {
          throw EvalError.typeMismatch("operand of unary ! must be a boolean")
        }
        return .boolean(!b)
      default:
        throw EvalError.invalidExpression("unary \(op) not allowed in member initializer")
      }

    case let .binaryExpr(lhs, op, rhs):
      let lhs = try evalInitializer(lhs, in: module)
      let rhs = try evalInitializer(rhs, in: module)
      switch lhs {
      case let .number(a):
        guard case let .number(b) = rhs else {
          throw EvalError.typeMismatch("operands of \(op) must be of same type")
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
          throw EvalError.typeMismatch("operands of \(op) must be of same type")
        }
        switch op {
        case .notEqual: return .boolean(a != b)
        case .equalEqual: return .boolean(a == b)
        default:
          throw EvalError.typeMismatch("operator \(op) cannot be applied to booleans")
        }

      default:
        throw EvalError.typeMismatch("invalid operands of \(op)")
      }

    case let .conjuction(lhs, rhs):
      let lhs = try evalInitializer(lhs, in: module)
      guard case let .boolean(a) = lhs else {
        throw EvalError.typeMismatch("expression before && must be a boolean")
      }
      if !a {
        return .boolean(false)
      } else {
        let rhs = try evalInitializer(rhs, in: module)
        guard case let .boolean(b) = rhs else {
          throw EvalError.typeMismatch("expression after && must be a boolean")
        }
        return .boolean(b)
      }

    case let .disjunction(lhs, rhs):
      let lhs = try evalInitializer(lhs, in: module)
      guard case let .boolean(a) = lhs else {
        throw EvalError.typeMismatch("expression before || must be a boolean")
      }
      if a {
        return .boolean(true)
      } else {
        let rhs = try evalInitializer(rhs, in: module)
        guard case let .boolean(b) = rhs else {
          throw EvalError.typeMismatch("expression after || must be a boolean")
        }
        return .boolean(b)
      }

    case let .list(nodes):
      let values = try nodes.map { try evalInitializer($0, in: module) }
      return .list(ValueList(values))

    case let .exit(portal, direction, destination):
      guard let portalRef = portal.asRef,
            let proto = lookup(portalRef, context: module)?.asEntity(Portal.self) else {
        throw EvalError.typeMismatch("invalid portal prototype")
      }
      guard let direction = Direction.fromValue(try evalInitializer(direction, in: module)) else {
        throw EvalError.typeMismatch("invalid portal direction")
      }
      guard let destinationRef = destination.asRef else {
        throw EvalError.typeMismatch("invalid portal destination")
      }
      let portal = proto.clone()
      portal.direction = direction
      portal.destination = destinationRef.toAbsolute(in: module)
      return .entity(portal)

    case let .stack(lhs, rhs):
      guard case let .number(n) = lhs, let count = Int(exactly: n) else {
        throw EvalError.typeMismatch("stack count must be an integer literal")
      }
      guard let protoRef = rhs.asRef,
            let proto = lookup(protoRef, context: module)?.asEntity(Item.self) else {
        throw EvalError.typeMismatch("invalid stack prototype")
      }
      let stack = proto.clone()
      stack.count = count
      return .entity(stack)

    case let .clone(lhs, _):  // FIXME:
      let lhs = try evalInitializer(lhs, in: module)
      guard case let .ref(ref) = lhs,
            case let .entity(proto) = lookup(ref, context: module) else {
        throw EvalError.typeMismatch("invalid entity prototype")
      }
      return .entity(proto.clone())

    case .dot:
      guard let ref = node.asRef else {
        throw EvalError.invalidExpression("invalid reference")
      }
      return .ref(ref)

    default:
      throw EvalError.invalidExpression("expression not allowed in member initializer")
    }
  }
}

extension World {
  static func schedule(delay: Double, block: @escaping () -> Void) {
    let when = DispatchTime.now() + delay
    DispatchQueue.main.asyncAfter(deadline: when, execute: DispatchWorkItem(block: block))
  }
}
