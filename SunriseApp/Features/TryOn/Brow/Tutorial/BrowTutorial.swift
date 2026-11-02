// -Nimah: Brows tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// The Brows tab's steps, as a brow is drawn with a pencil after brow mapping.
    static let browLessons = [
        FaceGuideLesson(title: String(localized: "Brush your brows up with your spoolie."),
                        instruction: String(localized: "Your brow hairs point up, and you can see the gaps.")),
        FaceGuideLesson(title: String(localized: "Mark three dots along the guide."),
                        instruction: String(localized: "Each brow has three small dots that sit on the guide's dots.")),
        FaceGuideLesson(title: String(localized: "Fill from the middle to the tail, lightly."),
                        instruction: String(localized: "The middle to tail is filled inside the guide. The front is still bare.")),
        FaceGuideLesson(title: String(localized: "Brush the middle into the front to blend."),
                        instruction: String(localized: "The front has soft colour with no hard starting edge.")),
        FaceGuideLesson(title: String(localized: "Wipe off anything outside the guide."),
                        instruction: String(localized: "The edges are clean, and nothing sits outside the guide.")),
    ]
}
