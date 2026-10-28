import Foundation

/// One reading of the camera and the phone. A nil value means "not measurable right now" and never triggers a message.
struct CameraSignals: Equatable, Sendable {
    /// `ARLightEstimate.ambientIntensity`, in lumens (about 1000 is neutral).
    var ambientIntensity: Double?
    var faceTracked = false
    /// Mean brightness of the face area divided by the mean of the whole frame.
    var faceLumaRatio: Double?
    /// Metres from the camera to the face.
    var distance: Double?
    var yawDegrees: Double?
    var rollDegrees: Double?
    /// Metres per second and degrees per second, averaged over about 0.3 s.
    var speed: Double?
    var turnRate: Double?
    /// How far the phone leans from upright, in degrees.
    var tiltDegrees: Double?
    var faceCount = 1
    var faceCovered = false
}

/// Decides which single message shows. Pure: the clock comes in as an argument, so it is easy to test.
/// Every threshold has a stricter value to show and a looser one to clear, so the caption does not flicker on the edge.
struct CameraMessageEngine {
    enum Limits {
        static let darkShow = 300.0, darkClear = 400.0
        static let backlitShow = 0.6, backlitClear = 0.7
        static let closeShow = 0.20, closeClear = 0.23
        static let farShow = 0.55, farClear = 0.50
        static let tiltShow = 25.0, tiltClear = 20.0
        static let yawShow = 25.0, yawClear = 20.0
        static let rollShow = 20.0, rollClear = 15.0
        static let speedShow = 0.3, speedClear = 0.2
        static let turnShow = 90.0, turnClear = 60.0
    }

    let context: CameraGuidanceContext
    private var raw = Set<CameraMessage>()
    private var rawSince: [CameraMessage: TimeInterval] = [:]
    private var clearSince: [CameraMessage: TimeInterval] = [:]
    private var shown = Set<CameraMessage>()
    private var seenFace = false

    init(context: CameraGuidanceContext) { self.context = context }

    /// Forget everything, as when the camera screen opens again.
    mutating func reset() { self = Self(context: context) }

    /// The message to show now, or nil.
    mutating func update(_ signals: CameraSignals, at now: TimeInterval) -> CameraMessage? {
        if signals.faceTracked { seenFace = true }
        for message in CameraMessage.allCases where message != .phoneWarm {
            let isRaw = condition(message, signals, wasRaw: raw.contains(message))
            if isRaw { raw.insert(message) } else { raw.remove(message) }
            if isRaw {
                clearSince[message] = nil
                let since = rawSince[message] ?? now
                rawSince[message] = since
                if now - since >= message.showDelay { shown.insert(message) }
            } else {
                rawSince[message] = nil
                guard shown.contains(message) else { continue }
                let since = clearSince[message] ?? now
                clearSince[message] = since
                if now - since >= CameraMessage.hideDelay { shown.remove(message); clearSince[message] = nil }
            }
        }
        return shown.min()
    }

    private func condition(_ message: CameraMessage, _ s: CameraSignals, wasRaw was: Bool) -> Bool {
        switch message {
        case .phoneWarm:
            return false
        case .tooDark:
            return s.ambientIntensity.map { Self.below($0, show: Limits.darkShow, clear: Limits.darkClear, was: was) } ?? false
        case .backlit:
            return s.faceLumaRatio.map { Self.below($0, show: Limits.backlitShow, clear: Limits.backlitClear, was: was) } ?? false
        case .noFace:
            // In the tutorial, losing the face after it was tracked is the "I'll wait here" message instead.
            return !s.faceTracked && !(context == .tutorial && seenFace)
        case .faceLost:
            return context == .tutorial && seenFace && !s.faceTracked
        case .multipleFaces:
            return s.faceCount > 1
        case .faceCovered:
            // In the tutorial her hand and brush are always near her face, so this one is Try On only.
            return context == .tryOn && s.faceTracked && s.faceCovered
        case .tooClose:
            return s.distance.map { Self.below($0, show: Limits.closeShow, clear: Limits.closeClear, was: was) } ?? false
        case .tooFar:
            return s.distance.map { Self.above($0, show: Limits.farShow, clear: Limits.farClear, was: was) } ?? false
        case .tiltedPhone:
            return s.tiltDegrees.map { Self.above($0, show: Limits.tiltShow, clear: Limits.tiltClear, was: was) } ?? false
        case .headTurned:
            let yaw = s.yawDegrees.map { Self.above($0, show: Limits.yawShow, clear: Limits.yawClear, was: was) } ?? false
            let roll = s.rollDegrees.map { Self.above($0, show: Limits.rollShow, clear: Limits.rollClear, was: was) } ?? false
            return yaw || roll
        case .movingFast:
            let speed = s.speed.map { Self.above($0, show: Limits.speedShow, clear: Limits.speedClear, was: was) } ?? false
            let turn = s.turnRate.map { Self.above($0, show: Limits.turnShow, clear: Limits.turnClear, was: was) } ?? false
            return speed || turn
        }
    }

    /// True below `show`; once true, stays true until above `clear` (`clear > show`).
    static func below(_ value: Double, show: Double, clear: Double, was: Bool) -> Bool { was ? value < clear : value < show }
    /// True above `show`; once true, stays true until below `clear` (`clear < show`).
    static func above(_ value: Double, show: Double, clear: Double, was: Bool) -> Bool { was ? value > clear : value > show }
}
