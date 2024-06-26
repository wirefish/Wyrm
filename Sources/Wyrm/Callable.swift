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
  func call(_ args: [Value], context: [Scope]) throws -> CallableResult
}

// A constraint on the argument value that can match a parameter when calling a
// script function.
enum Constraint: Equatable {
  // Any argument matches.
  case none

  // The argument must be the entity on which the function or handler is defined.
  case `self`

  // The argument must be an entity that has the specified entity in its prototype chain.
  case prototype(Ref)

  // The argument must be an avatar that is currently at the specified phase
  // of the specified quest. In addition to the phases defined by the quest,
  // the following pseudo-phases can be used:
  //
  // "available" means the quest can be offered;
  // "offered" means the quest has been offered but not accepted;
  // "incomplete" means the quest has been accepted but not completed; and
  // "complete" means the quest has been completed.
  case quest(Ref, String)

  // The argument must be an avatar with the specified race.
  case race(Ref)

  // The argument must be an avatar with the specified item equipped.
  case equipped(Ref)
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

  func call(_ args: [Value], context: [Scope]) throws -> CallableResult {
    return try World.instance.exec(self, args: args, context: context + [module])
  }
}

class BoundMethod: Callable {
  let object: Value
  let method: Callable

  init<T: ValueRepresentable>(object: T, method: Callable) {
    self.object = object.toValue()
    self.method = method
  }

  func call(_ args: [Value], context: [Scope]) throws -> CallableResult {
    return try method.call([object] + args, context: context)
  }
}
