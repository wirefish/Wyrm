//
//  World.swift
//  Wyrm
//

import CoreFoundation
import Dispatch

class Module: Scope {
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

enum Ref: Hashable {
  case absolute(String, String)
  case relative(String)
}

extension Ref: Codable, CustomStringConvertible {
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
    case let .absolute(module, name): "\(module).\(name)"
    case let .relative(name): name
    }
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
  var handlers = EventHandlers()
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
  var initializers = [BoundMethod]()

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
                          ("fixture", Thing()),
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

  func lookup(_ ref: Ref, context: [Scope]) -> Value? {
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

  func lookup(_ ref: Ref, context: Scope? = nil) -> Value? {
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
    let event = Event(phase: .when, name: "startWorld")
    for location in locations {
      location.respondTo(event, args: [])
      for entity in location.contents {
        entity.location = location
        entity.respondTo(event, args: [])
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

    logger.info("running \(initializers.count) initializers")
    for initializer in initializers {
      do {
        let _ = try initializer.call([], context: [])
      } catch {
        logger.warning("error in initializer for \(initializer.object): \(error)")
      }
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

  private func createInitializer<T: ValueRepresentable & Scope>
  (object: T, members: [Definition.Member], in module: Module) {
    if !members.isEmpty {
      let compiler = Compiler()
      let fn = compiler.compileInitializer(members: members, in: module)
      initializers.append(BoundMethod(object: object, method: fn))
    }
  }

  private func addSelf(_ params: [Parameter]) -> [Parameter] {
    [Parameter(name: "self", constraint: .none)] + params
  }

  private func compileEventHandlers(_ handlers: [Definition.Handler],
                                    in module: Module) -> EventHandlers {
    var result = EventHandlers()
    for (event, params, body) in handlers {
      let compiler = Compiler()
      if let fn = compiler.compileFunction(parameters: addSelf(params), body: body, in: module) {
        result[event, default: []].append(fn)
      }
    }
    return result
  }

  private func compileMethods(_ methods: [Definition.Method], in module: Module) -> [String:Value] {
    var members = [String:Value]()
    for (name, params, body) in methods {
      let compiler = Compiler()
      if let fn = compiler.compileFunction(parameters: addSelf(params), body: body, in: module) {
        members[name] = .function(fn)
      }
    }
    return members
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

    createInitializer(object: entity, members: members, in: module)
    entity.handlers = compileEventHandlers(handlers, in: module)
    entity.members = compileMethods(methods, in: module)

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

    createInitializer(object: quest, members: members, in: module)

    for (phaseName, members) in phases {
      let phase = QuestPhase(phaseName)
      createInitializer(object: phase, members: members, in: module)
      quest.phases.append(phase)
    }

    module.bindings[name] = .quest(quest)
  }

  private func loadRace(_ node: Definition, into module: Module) {
    guard case let .race(name, members) = node else {
      fatalError("invalid call to loadRace")
    }
    let race = Race(ref: .absolute(module.name, name))
    createInitializer(object: race, members: members, in: module)
    module.bindings[name] = .race(race)
  }

  private func loadSkill(_ node: Definition, into module: Module) {
    guard case let .skill(name, members) = node else {
      fatalError("invalid call to loadSkill")
    }
    let skill = Skill(ref: .absolute(module.name, name))
    createInitializer(object: skill, members: members, in: module)
    module.bindings[name] = .skill(skill)
  }

  private func loadRegion(_ node: Definition, into module: Module) {
    guard case let .region(members) = node else {
      fatalError("invalid call to loadRegion")
    }
    let region = Region()
    createInitializer(object: region, members: members, in: module)

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
    ext.handlers = compileEventHandlers(handlers, in: module)
    ext.methods = compileMethods(methods, in: module)
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
      entity.handlers.merge(ext.handlers) { (old, new) -> [ScriptFunction] in
        new + old
      }
      entity.members.merge(ext.methods) { (old, new) -> Value in
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
        guard let destination = portal.destination else {
          logger.warning("portal \(portal.direction) from \(location.ref!) has no destination")
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
        guard twin.destination! === location else {
          logger.warning("twin of portal \(portal.direction) from \(location.ref!) has mismatched destination \(twin.destination!.ref!)")
          continue
        }
        portal.twin = twin
        twin.twin = portal
      }
    }
  }
}

extension World {
  static func schedule(delay: Double, block: @escaping () -> Void) {
    let when = DispatchTime.now() + delay
    DispatchQueue.main.asyncAfter(deadline: when, execute: DispatchWorkItem(block: block))
  }
}
