//
//  ScriptLibrary.swift
//  Wyrm
//
//  Created by Craig Becker on 6/26/22.
//

struct NativeFunction: Callable {
    let name: String
    let fn: ([Value]) throws -> Value

    func call(_ args: [Value], context: [ValueDictionary]) throws -> Value? {
        return try fn(args)
    }
}

enum ScriptError: Error {
    case invalidArgument
    case wrongNumberOfArguments(got: Int, expected: Int)
}

struct ScriptLibrary {
    static func unpack<T1: ValueRepresentable>(_ args: [Value], _ t1: T1.Type) throws -> T1 {
        guard args.count == 1 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 1)
        }
        guard let v1 = T1.init(fromValue: args[0]) else {
            throw ScriptError.invalidArgument
        }
        return v1
    }

    static func trunc(_ args: [Value]) throws -> Value {
        let x = try unpack(args, Double.self)
        return .number(x.rounded(.towardZero))
    }

    static func logDebug(_ args: [Value]) throws -> Value {
        logger.debug(args.map({ String(describing: $0) }).joined(separator: " "))
        return .nil
    }

    static func show(_ args: [Value]) throws -> Value {
        // TODO:
        return .nil
    }

    static let functions = [
        ("log_debug", logDebug),
        ("trunc", trunc),
        ("show", show),
    ]
}
