//
//  Vendor.swift
//  Wyrm
//

let buyHelp = """
Use the `buy` command to purchase items from a vendor.
"""

let buyCommand = Command("buy item from:vendor", help: buyHelp) { actor, verb, clauses in
  var vendors = actor.location.contents.compactMap { (e) -> Creature? in
    guard let creature = e as? Creature,
          creature.isVisible(to: actor) && creature.sells != nil else {
      return nil
    }
    return creature
  }
  if case let .tokens(vendorTokens) = clauses[1] {
    guard let matches = match(vendorTokens, against: vendors) else {
      actor.show("There's no vendor like that here.")
      return
    }
    vendors = matches.matches
  } else if vendors.isEmpty {
    actor.show("There are no vendors here.")
    return
  }
  if vendors.count > 1 {
    actor.show("Do you want to buy from \(vendors.describe(using: "or"))?")
    return
  }
  let vendor = vendors[0]
  let items = vendor.sells!.compactMap { $0.deref()?.asEntity(Item.self) }

  guard case let .tokens(itemTokens) = clauses[0] else {
    let info = items.map {
      "\($0.describeBriefly([.plural])) for \($0.price!.describeBriefly())"
    }.conjunction(using: "and")
    actor.show("\(vendor.describeBriefly([.capitalized, .definite])) sells the following items: \(info).")
    return
  }
  guard let itemMatches = match(itemTokens, against: items) else {
    actor.show("\(vendor.describeBriefly([.capitalized, .definite])) doesn't sell anything like that.")
    return
  }
}
