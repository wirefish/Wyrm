//
//  ScriptLibrary.swift
//  Wyrm
//

enum ScriptError: Error {
    case invalidArgument
    case wrongNumberOfArguments(got: Int, expected: Int)
}

protocol ScriptProvider {
    static var functions: [(String, ([Value]) throws -> Value)] { get }
}

// Helper functions to unpack a value array into a specific number of values of specific types.
extension ScriptProvider {
    static func unpack<T1: ValueRepresentable>
    (_ args: [Value], _ t1: T1.Type) throws -> T1 {
        guard args.count == 1 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 1)
        }
        guard let v1 = T1.fromValue(args[0]) else {
            throw ScriptError.invalidArgument
        }
        return v1
    }

    static func unpack<T1: ValueRepresentable, T2: ValueRepresentable>
    (_ args: [Value], _ t1: T1.Type, _ t2: T2.Type) throws -> (T1, T2) {
        guard args.count == 2 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 2)
        }
        guard let v1 = T1.fromValue(args[0]),
              let v2 = T2.fromValue(args[1]) else {
            throw ScriptError.invalidArgument
        }
        return (v1, v2)
    }

    static func unpack<T1: ValueRepresentable, T2: ValueRepresentable, T3: ValueRepresentable>
    (_ args: [Value], _ t1: T1.Type, _ t2: T2.Type, _ t3: T3.Type) throws -> (T1, T2, T3) {
        guard args.count == 3 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 3)
        }
        guard let v1 = T1.fromValue(args[0]),
              let v2 = T2.fromValue(args[1]),
              let v3 = T3.fromValue(args[2]) else {
            throw ScriptError.invalidArgument
        }
        return (v1, v2, v3)
    }
}

struct ScriptLibrary: ScriptProvider {
    static let functions = [
        ("change_race", changeRace),
        ("log_debug", logDebug),
        ("random", random),
        ("show", show),
        ("show_tutorial", showTutorial),
        ("sleep", sleep),
        ("spawn", spawn),
        ("tell", tell),
        ("trunc", trunc),
    ]

    static func trunc(_ args: [Value]) throws -> Value {
        let x = try unpack(args, Double.self)
        return .number(x.rounded(.towardZero))
    }

    static func random(_ args: [Value]) throws -> Value {
        let (min, max) = try unpack(args, Double.self, Double.self)
        return .number(Double.random(in: min...max))
    }

    static func logDebug(_ args: [Value]) throws -> Value {
        logger.debug(args.map({ String(describing: $0) }).joined(separator: " "))
        return .nil
    }

    static func show(_ args: [Value]) throws -> Value {
        let (avatar, message) = try unpack(args, Avatar.self, String.self)
        avatar.show(message)
        return .nil
    }

    static func showTutorial(_ args: [Value]) throws -> Value {
        let (avatar, key, message) = try unpack(args, Avatar.self, String.self, String.self)
        avatar.showTutorial(key, message)
        return .nil
    }

    static func tell(_ args: [Value]) throws -> Value {
        let (actor, avatar, message) = try unpack(args, PhysicalEntity.self, Avatar.self, String.self)
        avatar.showSay(actor, "says", message, false)
        return .nil
    }

    static func changeRace(_ args: [Value]) throws -> Value {
        let (avatar, race) = try unpack(args, Avatar.self, Race.self)
        avatar.race = race
        avatar.showNotice("You are now \(race.describeBriefly([.indefinite]))!")
        return .nil
    }

    static func spawn(_ args: [Value]) throws -> Value {
        let (entity, location, delay) = try unpack(args, PhysicalEntity.self, Location.self, Double.self)
        World.schedule(delay: delay) {
            // FIXME:
            location.insert(entity.clone())
        }

        return .nil
    }

    static func sleep(_ args: [Value]) throws -> Value {
        let delay = try unpack(args, Double.self)
        return .future { fn in
            World.schedule(delay: delay) { fn() }
        }
    }
}
