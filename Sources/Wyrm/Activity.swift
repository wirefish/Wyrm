//
//  Activity.swift
//  Wyrm
//

protocol Activity: AnyObject {
    var name: String { get }
    func begin()
    func cancel()
}

protocol Actor: AnyObject {
    var activity: Activity? { get set }
    func beginActivity(_ activity: Activity)
    func cancelActivity()
    func activityFinished()
}

extension Actor {
    func beginActivity(_ activity: Activity) {
        cancelActivity()
        self.activity = activity
        activity.begin()
    }

    func cancelActivity() {
        if let activity = self.activity {
            self.activity = nil
            activity.cancel()
        }
    }

    func activityFinished() {
        self.activity = nil
    }
}

extension Avatar: Actor {}
