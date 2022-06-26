//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import Foundation

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
}

enum WorldError: Error {
    case invalidModuleSpec(String)
}

class World {
    let rootPath: String
    var modules = [String:Module]()
    let coreModule = Module("__CORE__")

    init(rootPath: String) {
        self.rootPath = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        for (name, fn) in ScriptLibrary.functions {
            coreModule.bindings[name] = .function(fn)
        }
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
            
        default:
            print("cannot evaluate expression \(node)")
            return nil
        }
    }

    func lookup(_ name: String, context: [ValueDictionary]) -> Value? {
        return context.firstMap { $0[name] } ?? coreModule[name]
    }

    func lookup(_ ref: EntityRef, context: Module) -> Entity? {
        if let moduleName = ref.module {
            return modules[moduleName]?.bindings[ref.name]?.asEntity
        } else if let value = context.bindings[ref.name] {
            return value.asEntity
        } else {
            return coreModule.bindings[ref.name]?.asEntity
        }
    }
}

// MARK: - loading files

extension World {

    func load() {
        let files = try! readModulesFile()

        for relativePath in files {
            let moduleName = moduleName(for: relativePath)
            let module = requireModule(named: moduleName)
            load(contentsOfFile: relativePath, into: module)
        }

        for (name, module) in modules {
            print(name, module.bindings.keys)
        }
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
        print("loading \(relativePath) into module \(module.name)")

        let source = try! String(contentsOfFile: rootPath + relativePath, encoding: .utf8)
        let parser = Parser(scanner: Scanner(source))
        for node in parser.parse() {
            switch node {
            case let .entity(name, prototypeRef, members, clone, handlers):
                var prototype: Entity?
                if prototypeRef != nil {
                    prototype = lookup(prototypeRef!, context: module)
                    if prototype == nil {
                        print("cannot find prototype \(prototypeRef!)")
                    }
                }
                let entity = Entity(withPrototype: prototype)
                let context: [ValueDictionary] = [entity, module]

                for member in members {
                    if let value = eval(member.initialValue, context: context) {
                        entity[member.name] = value
                    }
                }

                module.bindings[name] = .entity(entity)

                print(name, entity)
                for facet in entity.facets {
                    let m = Mirror(reflecting: facet)
                    print(m.description)
                    for (label, value) in m.children {
                        print("  \(label!) = \(value)")
                    }
                }

            default:
                break
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
