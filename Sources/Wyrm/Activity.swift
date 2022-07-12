//
//  Activity.swift
//  Wyrm
//

protocol Activity: AnyObject {
    func begin(_ avatar: Avatar) -> Double
    func cancel(_ avatar: Avatar)
    func finish(_ avatar: Avatar)
}

extension Avatar {
    func cancelActivity() {
        if let activity = self.activity {
            self.activity = nil
            self.sendMessage("stopPlayerCast")
            activity.cancel(self)
        }
    }

    func beginActivity(_ activity: Activity) {
        cancelActivity()
        self.activity = activity
        let t = activity.begin(self)
        World.schedule(delay: t) { [weak self, weak activity] in
            if let self = self, let activity = activity {
                self.activity = nil
                self.sendMessage("stopPlayerCast")
                activity.finish(self)
            }
        }
        sendMessage("startPlayerCast", .double(t))
    }
}
