import Combine
import Foundation

/// The latest face shape scan, shared by onboarding and the Try On home screen.
/// When given `UserDefaults`, only the classified result is kept on device so onboarding runs once; no images or meshes are saved.
@MainActor final class FaceShapeStore: ObservableObject {
    static let latestKey = "latestFaceShapeResult"
    static let latestEyesKey = "latestEyeShapeResult"

    @Published var latest: FaceShapeResult? {
        didSet { save() }
    }
    /// The latest eye scan; kept separately so a face rescan does not throw it away.
    @Published var eyes: EyeShapeResult? {
        didSet { saveEyes() }
    }
    private let defaults: UserDefaults?

    /// In memory only, for previews and tests.
    init(latest: FaceShapeResult? = nil, eyes: EyeShapeResult? = nil) {
        self.latest = latest
        self.eyes = eyes
        defaults = nil
    }

    /// Restores the result saved by a previous launch.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        latest = defaults.data(forKey: Self.latestKey)
            .flatMap { try? JSONDecoder().decode(FaceShapeResult.self, from: $0) }
        eyes = defaults.data(forKey: Self.latestEyesKey)
            .flatMap { try? JSONDecoder().decode(EyeShapeResult.self, from: $0) }
    }

    private func saveEyes() {
        guard let defaults else { return }
        if let eyes, let data = try? JSONEncoder().encode(eyes) {
            defaults.set(data, forKey: Self.latestEyesKey)
        } else {
            defaults.removeObject(forKey: Self.latestEyesKey)
        }
    }

    private func save() {
        guard let defaults else { return }
        if let latest, let data = try? JSONEncoder().encode(latest) {
            defaults.set(data, forKey: Self.latestKey)
        } else {
            defaults.removeObject(forKey: Self.latestKey)
        }
    }
}
