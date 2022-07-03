//
//  Quest.swift
//  Wyrm
//
//  Created by Craig Becker on 6/28/22.
//

protocol Interactable {
    var offers_quests: [Quest] { get }
    // TODO: interaction_verbs that are like implied commands, if the user enters an unknown
    // command it parses the rest of the input and matches it against entities at the current
    // location, then if they have a matching verb it generates events for that verb.
}

class QuestPhase: ValueDictionaryObject {
    let label: String
    var summary = ""
    var initialState = Value.nil

    init(_ label: String) {
        self.label = label
    }

    static let accessors = [
        "summary": accessor(\QuestPhase.summary),
        "initial_state": accessor(\QuestPhase.initialState),
    ]
}

class Quest: ValueDictionaryObject, CustomDebugStringConvertible {
    let ref: ValueRef
    var name = ""
    var summary = ""
    var level = 1
    var phases = [QuestPhase]()

    init(ref: ValueRef) {
        self.ref = ref
    }

    static let accessors = [
        "name": accessor(\Quest.name),
        "summary": accessor(\Quest.summary),
        "level": accessor(\Quest.level),
    ]

    var handlers = [EventHandler]()

    var debugDescription: String { "<Quest \(ref)>" }

    func acceptableBy(_ avatar: Avatar) -> Bool {
        // TODO: call out to quest method
        return (avatar.level >= level
                && avatar.activeQuests[ref] == nil
                && avatar.completedQuests[ref] == nil)
    }

    func completeableBy(_ avatar: Avatar) -> Bool {
        // TODO: what determines this? A specific state value I guess?
        return false
    }
}

extension Entity {
    // Returns true if this entity has an event handler constrained to a
    // specific quest and phase, indicating that it is involved in advancing the
    // quest. This is used to mark entities on the map, etc.
    func advancesQuest(_ quest: Quest, phase: String) -> Bool {
        return handlers.contains {
            $0.fn.parameters.contains {
                if case let .quest(r, p) = $0.constraint {
                    return quest.ref == r && phase == p
                } else {
                    return false
                }
            }
        }
    }
}

// Avatar methods related to managing quests.
extension Avatar {
    func acceptQuest(_ quest: Quest) -> Bool {
        guard let phase = quest.phases.first else {
            logger.warning("cannot accept quest \(quest.name) with no phases")
            return false
        }
        activeQuests[quest.ref] = QuestState(phase: phase.label, state: phase.initialState)
        return true
    }

    func advanceQuest(_ quest: Quest, to phaseLabel: String) -> Bool {
        guard let phase = quest.phases.first(where: { $0.label == phaseLabel }) else {
            logger.warning("cannot advance quest \(quest.name) to unknown phase \(phaseLabel)")
            return false
        }
        activeQuests.updateValue(QuestState(phase: phaseLabel, state: phase.initialState),
                                 forKey: quest.ref)
        return true
    }

    func dropQuest(_ quest: Quest) -> Bool {
        guard activeQuests.removeValue(forKey: quest.ref) != nil else {
            logger.warning("cannot drop quest \(quest.name) that is not active")
            return false
        }
        // TODO: remove quest items
        return true
    }

    func completeQuest(_ quest: Quest) -> Bool {
        // TODO:
        return false
    }

    func didCompleteQuest(_ quest: Quest) -> Bool {
        return completedQuests[quest.ref] != nil
    }
}

struct QuestScriptFunctions: ScriptProvider {
    static let functions = [
        ("accept_quest", acceptQuest),
    ]

    static func acceptQuest(_ args: [Value]) throws -> Value {
        /* FIXME:
        let (actor, quest, npc) = try unpack(args, Entity.self, Quest.self, Entity.self)
        guard let avatar = actor as? Avatar else {
            throw ScriptError.invalidArgument
        }
        avatar.acceptQuest(quest)
        // fire event: after accept_quest(avatar, quest, noc)
         */
        return .nil
    }
}
