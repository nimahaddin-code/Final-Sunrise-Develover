import ARKit
import CoreMotion
import SwiftUI

/// Watches the shared face camera and the phone, and publishes the one message that should show (or nil).
/// It only reads `ARSession.currentFrame`; the session and its delegate stay with `LiveGuideView`. Nothing is stored.
@MainActor final class CameraAdvisor: ObservableObject {
    /// The message on screen. Nil when the setup is fine.
    @Published private(set) var message: CameraMessage?
    @Published private(set) var thermal = ProcessInfo.processInfo.thermalState
    /// Changes each time "too dark" starts showing, so the light button can pulse once.
    @Published private(set) var darkPulse = 0

    private let session: ARSession
    private let sampler: CameraSignalSampler
    private var engine: CameraMessageEngine
    private var loop: Task<Void, Never>?
    private var thermalObserver: NSObjectProtocol?
    private let motion = CMMotionManager()
    private var tilt: Double?

    init(context: CameraGuidanceContext, session: ARSession = ARFaceTrackingManager.shared.session) {
        self.session = session
        engine = CameraMessageEngine(context: context)
        sampler = CameraSignalSampler(detectsCoverage: context == .tryOn)
    }

    /// While a message shows, the makeup preview or AR guide fades to 30% and the step animation pauses.
    var isDimmed: Bool { message != nil }
    /// Serious heat: the AR session drops to 30 fps and the step animation loop stops. No message.
    var reducesLoad: Bool { thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
    /// Critical heat: the AR session pauses until the phone cools down.
    var pausesSession: Bool { thermal == .critical }
    var pausesAnimation: Bool { isDimmed || reducesLoad }

    func start() {
        guard loop == nil else { return }
        engine.reset()
        sampler.reset()
        thermal = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermalChanged() }
        }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let gravity = data?.gravity else { return }
                // Upright in portrait is gravity along -y; flat is 90 degrees.
                let angle = acos(min(max(-gravity.y, -1), 1)) * 180 / .pi
                Task { @MainActor in self?.tilt = angle }
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                await self?.tick()
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        motion.stopDeviceMotionUpdates()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        thermalObserver = nil
        tilt = nil
        message = nil
    }

    private func thermalChanged() {
        let previous = thermal
        thermal = ProcessInfo.processInfo.thermalState
        if previous == .critical, thermal != .critical { engine.reset(); message = nil }
        if thermal == .critical { message = .phoneWarm }
    }

    private func tick() async {
        guard thermal != .critical else { message = .phoneWarm; return }
        // No fresh frame means the session is not running (starting, paused, or another screen owns it): say nothing.
        guard let frame = session.currentFrame, ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.7 else { return }
        var signals = await sampler.sample(.init(frame: frame), visionEnabled: !reducesLoad)
        guard !Task.isCancelled, thermal != .critical else { return }
        signals.tiltDegrees = tilt
        let next = engine.update(signals, at: ProcessInfo.processInfo.systemUptime)
        guard next != message else { return }
        if next == .tooDark { darkPulse += 1 }
        message = next
    }
}
