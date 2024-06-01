//
//  Gathering.swift
//  Wyrm
//

// MARK: - ResourceNode

class ResourceNode: Thing {
    // The skill required to see and use the node.
    var requiredSkill: Ref?

    // The minimum skill rank required to see and use the node. This rank
    // corresponds to a 50% chance of successfully gathering from the node.
    var minRank = 1

    // The skill rank corresponding to a 100% success rate. This is also the
    // rank at which using the node can no longer grant a rank increase.
    var maxRank = 100

    // The type of tool that must be equipped to use the node.
    var requiredTool: Ref?

    // The amount of time it takes to gather at the node.
    var duration = 3.0

    // The resources that can potentially be received after successful use of
    // the node.
    var yield: LootTable?

    // The time in seconds before the node respawns after being used.
    var respawn = 300.0

    override func copyProperties(from other: Entity) {
        let other = other as! ResourceNode
        requiredSkill = other.requiredSkill
        minRank = other.minRank
        maxRank = other.maxRank
        requiredTool = other.requiredTool
        duration = other.duration
        yield = other.yield
        respawn = other.respawn
        super.copyProperties(from: other)
    }

    private static let accessors = [
        "requiredSkill": Accessor(\ResourceNode.requiredSkill),
        "minRank": Accessor(\ResourceNode.minRank),
        "maxRank": Accessor(\ResourceNode.maxRank),
        "requiredTool": Accessor(\ResourceNode.requiredTool),
        "duration": Accessor(\ResourceNode.duration),
        "yield": Accessor(\ResourceNode.yield),
        "respawn": Accessor(\ResourceNode.respawn),
   ]

    override func get(_ member: String) -> Value? {
        getMember(member, Self.accessors) ?? super.get(member)
    }

    override func set(_ member: String, to value: Value) throws {
        try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
    }
}

// MARK: - Gathering activity

class Gathering: Activity {
    let name = "gathering"
    weak var avatar: Avatar?
    weak var node: ResourceNode?

    init(_ avatar: Avatar, node: ResourceNode) {
        self.avatar = avatar
        self.node = node
    }

    func begin() {
        if let avatar = avatar, let node = node {
            avatar.show("You begin to gather from \(node.describeBriefly([.definite])).")
            avatar.sendMessage("startPlayerCast", .double(node.duration))
            World.schedule(delay: node.duration) { self.finish() }
        }
    }

    func cancel() {
        if let avatar = self.avatar {
            avatar.show("Your gathering attempt is interrupted.")
            avatar.sendMessage("stopPlayerCast")
        }
        self.avatar = nil
        self.node = nil
    }

    func finish() {
        if let avatar = avatar {
            avatar.sendMessage("stopPlayerCast")
            avatar.activityFinished()
            if let node = node, let yield = node.yield {
                avatar.show("You finish gathering.")
                triggerEvent("gather", in: avatar.location, participants: [avatar, node],
                             args: [avatar, node]) {
                    let items = yield.generateItems()
                    avatar.receiveItems(items, from: node)
                }
            } else {
                avatar.show("Your gathering attempt failed.")
            }
        }
    }
}

// MARK: - gather command

let gatherHelp = """
Use the `gather` command to collect resources from a nearby resource node, such
as a mineral deposit or a mature tree. You will need to have attained a certain
rank in a specific skill in order to gather successfully. In addition, you will
need to have an appropriate tool equipped. A higher skill rank or higher-level
tool can increase your chance of success.
"""

let gatherCommand = Command("gather from:node", help: gatherHelp) { actor, verb, clauses in
    // Select the resource node.
    var candidates = actor.location.contents.filter {
        $0 is ResourceNode && $0.isVisible(to: actor)
    }
    if case let .tokens(target) = clauses[0] {
        guard let matches = match(target, against: candidates) else {
            actor.show("There's nothing like that here to gather from.")
            return
        }
        candidates = matches.matches
    } else if candidates.isEmpty {
        actor.show("There's nothing here to gather from.")
        return
    }
    if candidates.count > 1 {
        actor.show("Do you want to gather from \(candidates.describe(using: "or"))?")
        return
    }
    let node = candidates[0] as! ResourceNode

    // Check rank.
    guard let skillRef = node.requiredSkill,
          case let .skill(skill) = World.instance.lookup(skillRef) else {
        actor.show("\(node.describeBriefly([.definite, .capitalized])) seems broken. Try again later.")
        return
    }
    guard actor.skills[skillRef, default: 0] >= node.minRank else {
        actor.show("You need to attain rank \(node.minRank) in \(skill.name!) to gather from \(node.describeBriefly([.definite])).")
        return
    }

    // Check tool.
    if let requiredTool = node.requiredTool {
        // FIXME: guard actor.hasEquipped(requiredTool) else { ... }
    }

    actor.beginActivity(Gathering(actor, node: node))
}
