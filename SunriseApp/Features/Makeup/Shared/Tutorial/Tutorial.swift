import Foundation

enum TutorialStep: String, CaseIterable, Identifiable, Sendable {
    case blush, contour, eyeshadow, eyeliner, lips
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Tutorial: Equatable, Sendable {
    let referenceID: String
    let steps: [TutorialStep]
}
