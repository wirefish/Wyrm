//
//  ScriptLibrary.swift
//  Wyrm
//
//  Created by Craig Becker on 6/26/22.
//

protocol Callable {
    func call(_ args: [Value]) throws -> Value?
}

extension Callable {
    func call(_ args: Value...) throws -> Value? {
        return try call(args)
    }
}

struct NativeFunction: Callable {
    let name: String
    let fn: ([Value]) throws -> Value

    func call(_ args: [Value]) throws -> Value? {
        return try fn(args)
    }
}

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
