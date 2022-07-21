//
//  Callable.swift
//  Wyrm
//

enum CallableResult {
    case value(Value)
    case await
    case `fallthrough`
}

protocol Callable {
    func call(_ args: [Value], context: [ValueDictionary]) throws -> CallableResult
}

// A constraint on the argument value that can match a parameter when calling a
// script function.
enum Constraint: Equatable {
    // Any argument matches.
    case none

    // The argument must be the entity on which the function or handler is defined.
    case `self`

    // The argument must be an entity that has the specified entity in its prototype chain.
    case prototype(ValueRef)

    // The argument must be an avatar that is currently at the specified phase of the
    // specified quest. The meta-phase "available" means the quest can be accepted; the
    // meta-phase "complete" means the quest has been completed.
    case quest(ValueRef, String)
}

struct Parameter {
    let name: String
    let constraint: Constraint
}

class ScriptFunction: Callable {
    weak var module: Module!
    let parameters: [Parameter]
    var constants = [Value]()
    var bytecode = [UInt8]()

    init(module: Module, parameters: [Parameter]) {
        self.module = module
        self.parameters = parameters
    }

    func call(_ args: [Value], context: [ValueDictionary]) throws -> CallableResult {
        do {
            return try World.instance.exec(self, args: args, context: context + [module])
        } catch {
            logger.warning("error in script function: \(error)")
            throw error
        }
    }
}

class BoundMethod: Callable {
    let entity: Entity
    let method: Callable

    init(entity: Entity, method: Callable) {
        self.entity = entity
        self.method = method
    }

    func call(_ args: [Value], context: [ValueDictionary]) throws -> CallableResult {
        return try method.call([.entity(entity)] + args, context: context)
    }
}
