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
        let compiler = Compiler()

        for relativePath in findFiles() {
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

    private func findFiles(_ relativeDir: String = "") -> [String] {
        guard let dir = opendir(rootPath + relativeDir) else {
            print("warning: cannot open directory \(rootPath + relativeDir)")
            return []
        }

        var files = [String]()
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { (rawPtr) -> String in
                let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
                return String(cString: ptr)
            }
            if name.hasPrefix(".") {
                // Skip this entry.
            } else if Int32(entry.pointee.d_type) & DT_DIR != 0 {
                files += findFiles(relativeDir + name + "/")
            } else if name.hasSuffix(".wyrm") {
                files.append(relativeDir + name)
            }
        }
        closedir(dir)

        return files
    }

    private func moduleName(for relativePath: String) -> String {
        if let sep = relativePath.lastIndex(of: "/") {
            return relativePath[..<sep].replacingOccurrences(of: "/", with: ".")
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
