// Lips tab of the guided tutorial. The shared tutorial screen, comparison and steps sheet are in Screens/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// Three steps for every lip shape (`LipStepGuide`); where the marks and the outline sit is what changes with the
    /// shape (for "Gradient" they are the middle of the lips, where the colour goes on).
    nonisolated static var lipLessons: [FaceGuideLesson] { [
        FaceGuideLesson(title: String(localized: "Mark the Shape"), instruction: String(localized: "Mark the points along the lip guide.")),
        FaceGuideLesson(title: String(localized: "Connect the Marks"),
                        instruction: String(localized: "Connect the marks to outline the shape.")),
        FaceGuideLesson(title: String(localized: "Fill In"),
                        instruction: String(localized: "Fill in the shape with lipstick, from the middle out.")),
    ] }
}
