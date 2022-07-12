//
//  Offer.swift
//  Wyrm
//

protocol Offer {
    func accept(_ avatar: Avatar)
    func decline(_ avatar: Avatar)
}

extension Avatar {
    func receiveOffer(_ offer: Offer) {
        cancelOffer()
        self.offer = offer
    }

    func cancelOffer() {
        if let offer = self.offer {
            offer.decline(self)
            self.offer = nil
        }
    }
}

let acceptHelp = """
Use the `accept` command to accept the most recent offer you have received. For
example, if an NPC offers you a quest, you use this command to accept it.
"""

let acceptCommand = Command("accept", help: acceptHelp) { actor, verb, clauses in
    if let offer = actor.offer {
        actor.offer = nil
        offer.accept(actor)
    } else {
        actor.show("You haven't been offered anything to accept.")
    }
}

let declineHelp = """
Use the `decline` command to explicitly decline the most recent offer you have
received. Note that offers are automatically declined in certain situations,
such as when you move to another location.
"""

let declineCommand = Command("decline", help: declineHelp) { actor, verb, clauses in
    if let offer = actor.offer {
        actor.offer = nil
        offer.decline(actor)
    } else {
        actor.show("You haven't been offered anything to decline.")
    }
}
