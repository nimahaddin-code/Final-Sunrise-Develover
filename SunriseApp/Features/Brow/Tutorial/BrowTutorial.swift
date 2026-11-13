// -Nimah: Brows tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// The Brows tab's steps: a short title (steps sheet) and the instruction shown over the camera.
    nonisolated static var browLessons: [FaceGuideLesson] { [
        FaceGuideLesson(title: String(localized: "Brush Your Brows"), instruction: String(localized: "Brush your brows up with a spoolie.")),
        FaceGuideLesson(title: String(localized: "Map Your Brows"), instruction: String(localized: "Grab your brow pencil and mark 3 points.")),
        FaceGuideLesson(title: String(localized: "Connect and Fill"), instruction: String(localized: "Connect the dots and fill from the middle out.")),
        FaceGuideLesson(title: String(localized: "Blend and Clean Up"), instruction: String(localized: "Blend the front and clean up.")),
    ] }

    /// `BrowTutorialOverlay`'s animation for each lesson: brush, dots, fill from the arch, then the front.
    static let browGuideSteps = [0, 1, 2, 3]
}
