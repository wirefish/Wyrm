//
//  World.swift
//  Wyrm
//
//  Created by Craig Becker on 6/25/22.
//

import Foundation

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

    init(rootPath: String) {
        self.rootPath = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
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
        // Parse all the files and create entities for all module-level
        // definitions.
        for relativePath in findFiles() {
            let nodes = parse(contentsOfFile: relativePath)
            print(nodes)

            let module = module(named: moduleName(for: relativePath))
            for node in nodes {
                if case let .entity(name, _, _, _) = node {
                    module.bindings[name] = .entity(Entity())
                }
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
