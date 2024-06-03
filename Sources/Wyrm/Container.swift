//
//  Container.swift
//  Wyrm
//

class Container: Thing {
  var contents = ItemCollection()

  var contentsPreposition = "in"

  var scriptContents: [ItemStack] { contents.stacks() }

  private static let accessors = [
    "capacity": Accessor(readOnly: \Container.contents.capacity),
    "count": Accessor(readOnly: \Container.contents.count),
    "contents": Accessor(readOnly: \Container.scriptContents)
  ]

  override func get(_ member: String) -> Value? {
    getMember(member, Self.accessors) ?? super.get(member)
  }

  override func set(_ member: String, to value: Value) throws {
    try setMember(member, to: value, Self.accessors) { try super.set(member, to: value) }
  }
}
