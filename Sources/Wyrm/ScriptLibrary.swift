//
//  ScriptLibrary.swift
//  Wyrm
//

enum ScriptError: Error {
    case invalidArgument
    case wrongNumberOfArguments(got: Int, expected: Int)
}

struct ScriptLibrary {
    static let functions = [
        ("add_exit", addExit),
        ("advance_quest", advanceQuest),
        ("announce", announce),
        ("change_gender", changeGender),
        ("change_name", changeName),
        ("change_race", changeRace),
        ("complete_quest", completeQuest),
        ("give_item", giveItem),
        ("isa", isa),
        ("len", len),
        ("log_debug", logDebug),
        ("offer_quest", offerQuest),
        ("opposite_direction", oppositeDirection),
        ("random", random),
        ("random_element", randomElement),
        ("receive_items", receiveItems),
        ("remove_exit", removeExit),
        ("show", show),
        ("show_near", showNear),
        ("show_tutorial", showTutorial),
        ("sleep", sleep),
        ("spawn", spawn),
        ("tell", tell),
        ("travel", travel),
        ("trunc", trunc),
    ]

    static func isa(_ args: [Value]) throws -> Value {
        let (entity, proto) = try unpack(args, Entity.self, Entity.self)
        if let ref = proto.ref {
            return .boolean(entity.isa(ref))
        } else {
            return .boolean(entity == proto)
        }
    }

    static func trunc(_ args: [Value]) throws -> Value {
        let x = try unpack(args, Double.self)
        return .number(x.rounded(.towardZero))
    }

    static func random(_ args: [Value]) throws -> Value {
        let (min, max) = try unpack(args, Double.self, Double.self)
        return .number(Double.random(in: min...max))
    }

    static func len(_ args: [Value]) throws -> Value {
        let list = try unpack(args, ValueList.self)
        return .number(Double(list.values.count))
    }

    static func randomElement(_ args: [Value]) throws -> Value {
        let list = try unpack(args, ValueList.self)
        return list.values.randomElement() ?? .nil
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

    static func showNear(_ args: [Value]) throws -> Value {
        let (actor, message) = try unpack(args, PhysicalEntity.self, String.self)
        actor.location.showAll(message)
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

    static func changeGender(_ args: [Value]) throws -> Value {
        let (avatar, gender) = try unpack(args, Avatar.self, Gender.self)
        avatar.gender = gender
        avatar.showNotice("You are now \(gender)!")
        return .nil
    }

    static func changeName(_ args: [Value]) throws -> Value {
        let (avatar, name) = try unpack(args, Avatar.self, String.self)
        // FIXME: more checks, capitalize
        if name.count >= 3 && name.count <= 15 {
            avatar.name = name
            avatar.showNotice("Your name is now \"\(name)\"!")
            return .boolean(true)
        } else {
            return .boolean(false)
        }
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

    static func addExit(_ args: [Value]) throws -> Value {
        let (portal, location) = try unpack(args, Portal.self, Location.self)
        return .boolean(location.addExit(portal))
    }

    static func removeExit(_ args: [Value]) throws -> Value {
        let (direction, location) = try unpack(args, Direction.self, Location.self)
        if let portal = location.removeExit(direction) {
            return .entity(portal)
        } else {
            return .nil
        }
    }

    static func oppositeDirection(_ args: [Value]) throws -> Value {
        let direction = try unpack(args, Direction.self)
        return direction.opposite.toValue()
    }

    static func announce(_ args: [Value]) throws -> Value {
        let (location, radius, message) = try unpack(args, Location.self, Int.self, String.self)
        let map = Map(at: location, radius: radius)
        for cell in map.cells {
            for entity in cell.location.contents {
                if let avatar = entity as? Avatar {
                    avatar.showNotice(message)
                }
            }
        }
        return .nil
    }

    static func travel(_ args: [Value]) throws -> Value {
        let (actor, exit) = try unpack(args, PhysicalEntity.self, Portal.self)
        guard let destRef = exit.destination,
              let dest = World.instance.lookup(destRef)?.asEntity(Location.self) else {
            return .boolean(false)
        }
        actor.travel(to: dest, direction: exit.direction, via: exit)
        return .boolean(true)
    }

    static func offerQuest(_ args: [Value]) throws -> Value {
        let (npc, quest, avatar) = try unpack(args, PhysicalEntity.self, Quest.self, Avatar.self)

        let b = triggerEvent("offer_quest", in: avatar.location, participants: [npc, avatar],
                             args: [npc, quest, avatar]) {
            avatar.receiveOffer(QuestOffer(questgiver: npc, quest: quest))
            avatar.showNotice("""
                \(npc.describeBriefly([.capitalized, .definite])) has offered you the quest
                "\(quest.name)". Type `accept` to accept it.
                """)
        }

        return .boolean(b)
    }

    static func advanceQuest(_ args: [Value]) throws -> Value {
        let (avatar, quest, progress) = try unpack(args, Avatar.self, Quest.self, Value?.self)
        return .boolean(avatar.advanceQuest(quest, by: progress))
    }

    static func completeQuest(_ args: [Value]) throws -> Value {
        let (avatar, quest) = try unpack(args, Avatar.self, Quest.self)
        avatar.completeQuest(quest)
        return .nil
    }

    static func giveItem(_ args: [Value]) throws -> Value {
        let (avatar, proto, target) = try unpack(args, Avatar.self, Item.self, PhysicalEntity.self)
        avatar.giveItems(to: target) { $0.prototype == proto }
        return .nil
    }

    static func receiveItems(_ args: [Value]) throws -> Value {
        let (avatar, items, source) = try unpack(args, Avatar.self, [Item].self, PhysicalEntity.self)
        avatar.receiveItems(items, from: source)
        return .nil
    }
}

// Helper functions to unpack a value array into a specific number of values of specific types.
extension ScriptLibrary {
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

    static func unpack<T1: ValueRepresentable, T2: ValueRepresentable, T3: ValueRepresentable>
    (_ args: [Value], _ t1: T1.Type, _ t2: T2.Type, _ t3: T3?.Type) throws -> (T1, T2, T3?) {
        guard args.count >= 2 && args.count <= 3 else {
            throw ScriptError.wrongNumberOfArguments(got: args.count, expected: 2)
        }
        guard let v1 = T1.fromValue(args[0]), let v2 = T2.fromValue(args[1]) else {
            throw ScriptError.invalidArgument
        }
        var v3: T3?
        if args.count == 3 {
            v3 = T3.fromValue(args[2])
            if v3 == nil {
                throw ScriptError.invalidArgument
            }
        }
        return (v1, v2, v3)
    }

}
