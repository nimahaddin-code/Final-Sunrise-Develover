// -Nimah: Eyeliner tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// Only the Arabian look has a lower line to mark and fill.
    var linerShowsLower: Bool { handoff.linerLook == .arabian }

    /// Three steps for every look (`LinerTutorialStep`); where the dots sit is what changes with the look.
    static let linerLessons = [
        FaceGuideLesson(title: String(localized: "Mark the Guide"), instruction: String(localized: "Mark 4 points along the eyeliner guide.")),
        FaceGuideLesson(title: String(localized: "Connect the Dots"),
                        instruction: String(localized: "Connect the dots to create a thin eyeliner outline.")),
        FaceGuideLesson(title: String(localized: "Fill and Finish"),
                        instruction: String(localized: "Fill in the eyeliner frame, keeping it close to your lashes.")),
    ]
}
