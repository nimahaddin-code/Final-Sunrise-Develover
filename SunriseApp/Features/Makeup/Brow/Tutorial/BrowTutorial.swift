// -Nimah: Brows tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// The Brows tab's steps, as a brow is drawn with a pencil after brow mapping: what to do, then a line of encouragement.
    static let browLessons = [
        FaceGuideLesson(title: String(localized: "Brush your brows up with your spoolie."),
                        instruction: String(localized: "Let's wake those brows up first! Seeing the gaps now makes everything easier later.")),
        FaceGuideLesson(title: String(localized: "Mark three tiny dots on the guide."),
                        instruction: String(localized: "These are your map. They don't have to be perfect, the guide's got you.")),
        FaceGuideLesson(title: String(localized: "Fill lightly from the middle out to the tail."),
                        instruction: String(localized: "Feather-light strokes, okay? Slow is smooth, and smooth is pretty.")),
        FaceGuideLesson(title: String(localized: "Brush the middle colour into the front."),
                        instruction: String(localized: "Keep the front soft and fluffy. You're nailing that natural look.")),
        FaceGuideLesson(title: String(localized: "Clean up anything outside the guide."),
                        instruction: String(localized: "Last touch! A little tidy-up and your brows are done. So proud of you.")),
    ]
}
