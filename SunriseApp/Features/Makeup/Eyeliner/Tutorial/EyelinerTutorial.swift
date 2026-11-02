// -Nimah: Eyeliner tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// Only the Arabian look has a lower line to mark and fill.
    var linerShowsLower: Bool { handoff.linerLook == .arabian }

    /// Three steps for every look (`LinerTutorialStep`). The screen takes its wording from the step, so these only count
    /// the steps; where the dots sit is what changes with the look.
    static let linerLessons: [FaceGuideLesson] = LinerTutorialStep.allCases.map {
        FaceGuideLesson(title: "Step \($0.rawValue + 1)", instruction: "")
    }
}
