import Combine
import Foundation

/// The latest face shape scan, shared by onboarding and the Try On home screen.
/// When given `UserDefaults`, only the classified result is kept on device so onboarding runs once; no images or meshes are saved.
@MainActor final class FaceShapeStore: ObservableObject {
    static let latestKey = "latestFaceShapeResult"

    @Published var latest: FaceShapeResult? {
        didSet { save() }
    }
    private let defaults: UserDefaults?

    /// In memory only, for previews and tests.
    init(latest: FaceShapeResult? = nil) {
        self.latest = latest
        defaults = nil
    }

    /// Restores the result saved by a previous launch.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        latest = defaults.data(forKey: Self.latestKey)
            .flatMap { try? JSONDecoder().decode(FaceShapeResult.self, from: $0) }
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
