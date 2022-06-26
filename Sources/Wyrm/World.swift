//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import Foundation

typealias ScriptFunction = ([Value]) throws -> Value

enum ScriptError: Error {
    case invalidArgument
    case wrongNumberOfArguments(got: Int, expected: Int)
}

// Methods to simplify unpacking values for use by native script functions.
extension Value {
    func asBool() throws -> Bool {
        guard case let .boolean(b) = self else {
            throw ScriptError.invalidArgument
        }
        return b
    }

    func asInt() throws -> Int {
        guard case let .number(n) = self else {
            throw ScriptError.invalidArgument
        }
        guard let i = Int(exactly: n) else {
            throw ScriptError.invalidArgument
        }
        return i
    }

    func asDouble() throws -> Double {
        guard case let .number(n) = self else {
            throw ScriptError.invalidArgument
        }
        return n
    }

    func asString() throws -> String {
        guard case let .string(s) = self else {
            throw ScriptError.invalidArgument
        }
        return s
    }
}

struct ScriptLibrary {
    static func unpack<T1>(_ args: [Value], _ m1: (Value) -> () throws -> T1) throws -> T1 {
        guard args.count == 1 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 1)
        }
        return try m1(args[0])()
    }

    static func trunc(_ args: [Value]) throws -> Value {
        let x = try unpack(args, Value.asDouble)
        return .number(x.rounded(.towardZero))
    }

    static let functions = [
        ("trunc", trunc),
    ]
}

class Module {
    let name: String
    var bindings = [String:Value]()

    init(_ name: String) {
        self.name = name
    }
}

enum ModuleError: Error {
    case invalidModuleSpec(String)
}

class World {
    let rootPath: String
    var modules = [String:Module]()

    static let coreModuleName = "__CORE__"

    init(rootPath: String) {
        self.rootPath = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        let core = Module(World.coreModuleName)
        for (name, fn) in ScriptLibrary.functions {
            core.bindings[name] = .function(fn)
        }
    }

    func module(named name: String) -> Module {
        if let module = modules[name] {
            return module
        } else {
            let module = Module(name)
            modules[name] = module
            return module
        }
    }

    func load() {
        let files = try! readModulesFile()

        let compiler = Compiler()

        for relativePath in files {
            let moduleName = moduleName(for: relativePath)
            print("loading \(relativePath) into module \(moduleName)")
            let nodes = parse(contentsOfFile: relativePath)
            print(nodes)

            for node in nodes {
                var block = CodeBlock()
                compiler.compile(node, &block)
                block.dump()
            }
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
                    throw ModuleError.invalidModuleSpec("directory name cannot be indented")
                }
                currentDir = item
            } else if indented {
                guard let dir = currentDir else {
                    throw ModuleError.invalidModuleSpec("indented filename has no directory")
                }
                files.append(dir + item + ".wyrm")
            } else {
                currentDir = nil
                files.append(item + ".wyrm")
            }
        }

        return files
    }

    private func moduleName(for relativePath: String) -> String {
        if let sep = relativePath.lastIndex(of: "/") {
            return relativePath[..<sep].replacingOccurrences(of: "/", with: "_")
        } else {
            return String(relativePath.prefix(while: { $0 != "." }))
        }
    }

    private func parse(contentsOfFile relativePath: String) -> [ParseNode] {
        let source = try! String(contentsOfFile: rootPath + relativePath, encoding: .utf8)
        let parser = Parser(scanner: Scanner(source))
        return parser.parse()
    }
}
