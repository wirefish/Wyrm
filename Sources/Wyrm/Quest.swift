//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

import CoreFoundation

struct QuestState: Codable {
    enum State: ValueRepresentable, Codable {
        case `nil`
        case number(Double)
        case numbers([Double])

        static func fromValue(_ value: Value) -> State? {
            switch value {
            case let .number(n):
                return .number(n)
            case let .list(list):
                let ns = list.values.map { Double.fromValue($0) }
                return ns.allSatisfy({ $0 != nil }) ? .numbers(ns.map { $0! }) : nil
            default:
                return nil
            }
        }

        func toValue() -> Value {
            switch self {
            case .nil: return .nil
            case let .number(n): return .number(n)
            case let .numbers(ns): return .list(ValueList(ns))
            }
        }
    }

    let phase: String
    var state: State
}

final class QuestPhase: ValueDictionaryObject {
    // The label that identifies the phase when defining the quest and when
    // calling advance_quest().
    let label: String

    // The summary shown to the player when they list active quests and are
    // currently in this phase.
    var summary = ""

    // The initial value of the quest state upon entering this phase.
    var initialState = QuestState.State.nil

    init(_ label: String) {
        self.label = label
    }

    static let accessors = [
        "summary": accessor(\QuestPhase.summary),
        "initial_state": accessor(\QuestPhase.initialState),
    ]
}

final class Quest: ValueDictionaryObject, CustomDebugStringConvertible, Matchable {
    let ref: ValueRef
    var name = ""
    var summary = ""
    var level = 1
    var requiredQuests = [ValueRef]()

    var phases = [QuestPhase]()

    init(ref: ValueRef) {
        self.ref = ref
    }

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
        "required_quests": accessor(\Quest.requiredQuests),
    ]

    var debugDescription: String { "<Quest \(ref)>" }

    func match(_ tokens: ArraySlice<String>) -> MatchQuality {
        return name.match(tokens)
    }

    func phase(_ label: String) -> QuestPhase? {
        return phases.first { $0.label == label }
    }

    func acceptableBy(_ avatar: Avatar) -> Bool {
        // TODO: other requirements
        return (avatar.level >= level
                && avatar.activeQuests[ref] == nil
                && avatar.completedQuests[ref] == nil
                && avatar.didCompleteQuests(requiredQuests))
    }

    func completableBy(_ avatar: Avatar) -> Bool {
        return avatar.activeQuests[ref]?.phase == phases.last!.label
    }
}

protocol Questgiver {
    var offersQuests: [Quest] { get }

    func advancesQuest(_ quest: Quest, phase: String) -> Bool
}

extension Questgiver {
    func offersQuestFor(_ avatar: Avatar) -> Bool {
        offersQuests.contains { $0.acceptableBy(avatar) }
    }

    func advancesQuestFor(_ avatar: Avatar) -> Bool {
        return avatar.activeQuests.contains { (ref, state) in
            guard case let .quest(quest) = ref.deref() else {
                return false
            }
            return advancesQuest(quest, phase: state.phase)
        }
    }

    func completesQuestFor(_ avatar: Avatar) -> Bool {
        return avatar.activeQuests.contains { (ref, state) in
            guard case let .quest(quest) = ref.deref(),
                  state.phase == quest.phases.last!.label else {
                return false
            }
            return advancesQuest(quest, phase: state.phase)
        }
    }
}

extension Entity {
    // Returns true if this entity has an event handler constrained to a
    // specific quest and phase, indicating that it is involved in advancing the
    // quest. This is used to mark entities on the map, etc.
    func advancesQuest(_ quest: Quest, phase: String) -> Bool {
        return handlers.contains { handler in
            handler.fn.parameters.contains {
                if case let .quest(r, p) = $0.constraint {
                    return quest.ref == r.toAbsolute(in: handler.fn.module) && phase == p
                } else {
                    return false
                }
            }
        } || (prototype?.advancesQuest(quest, phase: phase) == true)
    }
}

struct QuestOffer: Offer {
    weak var questgiver: PhysicalEntity?
    let quest: Quest

    func accept(_ avatar: Avatar) {
        guard let questgiver = questgiver, quest.acceptableBy(avatar) else {
            avatar.showNotice("You can no longer accept the quest \"\(quest.name)\".")
            return
        }

        triggerEvent("accept_quest", in: avatar.location, participants: [avatar, questgiver],
                             args: [avatar, quest, questgiver]) {
            let phase = quest.phases.first!
            avatar.activeQuests[quest.ref] = QuestState(phase: phase.label, state: phase.initialState)
            avatar.showNotice("You have accepted the quest \"\(quest.name)\".")
        }

        // FIXME:
        avatar.showMap()
    }

    func decline(_ avatar: Avatar) {
        avatar.showNotice("You have declined the offer to accept the quest \"\(quest.name)\".")
    }
}

// Avatar methods related to managing quests.
extension Avatar {
    func advanceQuest(_ quest: Quest, to phaseLabel: String) -> Bool {
        guard let phase = quest.phase(phaseLabel) else {
            logger.warning("cannot advance quest \(quest.name) to unknown phase \(phaseLabel)")
            return false
        }
        activeQuests.updateValue(QuestState(phase: phaseLabel, state: phase.initialState),
                                 forKey: quest.ref)

        // FIXME:
        showMap()

        return true
    }

    func dropQuest(_ quest: Quest) {
        guard activeQuests.removeValue(forKey: quest.ref) != nil else {
            logger.warning("cannot drop quest \(quest.name) that is not active")
            return
        }

        discardItems { $0.quest == quest.ref }

        // FIXME:
        showMap()
    }

    func completeQuest(_ quest: Quest) {
        activeQuests[quest.ref] = nil
        completedQuests[quest.ref] = Int(CFAbsoluteTimeGetCurrent() / 60)
        showNotice("You have completed the quest \"\(quest.name)\"!")

        // Clean up forgotten quest items.
        discardItems { $0.quest == quest.ref }

        // FIXME:
        showMap()
    }

    func didCompleteQuest(_ quest: Quest) -> Bool {
        return completedQuests[quest.ref] != nil
    }

    func didCompleteQuests(_ refs: [ValueRef]) -> Bool {
        refs.allSatisfy { completedQuests[$0] != nil }
    }
}

struct QuestScriptFunctions: ScriptProvider {
    static let functions = [
        ("advance_quest", advanceQuest),
        ("complete_quest", completeQuest),
        ("give_item", giveItem),
        ("offer_quest", offerQuest),
        ("receive_items", receiveItems),
    ]

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
        let (avatar, quest, phase) = try unpack(args, Avatar.self, Quest.self, String.self)
        _ = avatar.advanceQuest(quest, to: phase)
        return .nil
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

let questHelp = """
Use the `quest` command to view information about your active quests or to drop
a quest you are no longer interested in completing.

Typing `quest` alone will display the current state of your active quests.

Typing `quest drop` followed by a quest name will drop an active quest. You will
lose all progress and items associated with the quest. You will need to accept
it and begin again if you decide to complete it in the future.
"""

let questCommand = Command("quest 1:subcommand name", help: questHelp) { actor, verb, clauses in
    if case let .string(subcommand) = clauses[0] {
        switch subcommand {
        case "drop":
            if case let .tokens(name) = clauses[1] {
                let quests = actor.activeQuests.keys.compactMap { key -> Quest? in
                    guard case let .quest(quest) = world.lookup(key) else {
                        return nil
                    }
                    return quest
                }
                if let matches = match(name, against: quests) {
                    if matches.count == 1 {
                        actor.dropQuest(matches.first!)
                        actor.showNotice("You are no longer on the quest \"\(matches.first!.name)\".")
                    } else {
                        actor.show("Do you want to drop \(matches.map { $0.name }.conjunction(using: "or"))?")
                    }
                } else {
                    actor.show("You don't have quests matching that description.")
                }
            } else {
                actor.show("Which quest do you want to drop?")
            }

        default:
            actor.show("Unrecognized subcommand \"\(subcommand)\".")
        }
    } else {
        let descriptions: [String] = actor.activeQuests.compactMap {
            let (ref, state) = $0
            guard case let .quest(quest) = world.lookup(ref) else {
                logger.warning("\(actor) has invalid active quest \(ref)")
                return nil
            }
            guard let phase = quest.phase(state.phase) else {
                logger.warning("\(actor) has invalid phase \(state.phase) for quest \(ref)")
                return nil
            }
            return "\(quest.name): \(phase.summary)"
        }

        if descriptions.isEmpty {
            actor.show("You have no active quests.")
        } else {
            actor.showList("You are on the following quests:", descriptions)
        }
    }
}
