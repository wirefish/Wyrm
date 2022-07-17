//
//  Activity.swift
//  Wyrm
//

protocol Activity: AnyObject {
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

class RepeatedActivity<T: Actor>: Activity {
    weak var actor: T?
    let firstDelay: Double
    let delay: Double
    let body: (T) -> Void

    init(actor: T, delay: Double, firstDelay: Double? = nil, body: @escaping (T) -> Void) {
        self.actor = actor
        self.firstDelay = firstDelay ?? delay
        self.delay = delay
        self.body = body
    }

    func begin() {
        World.schedule(delay: firstDelay) { self.perform() }
    }

    func cancel() {
        self.actor = nil
    }

    private func perform() {
        if let actor = self.actor {
            self.body(actor)
            World.schedule(delay: self.delay) { self.perform() }
        }
    }
}

extension Avatar: Actor {}
