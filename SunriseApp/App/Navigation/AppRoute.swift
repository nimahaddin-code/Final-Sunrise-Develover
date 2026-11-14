import Foundation

enum AppTab: Hashable { case tryOn, discover, myLooks }

/// The makeup flow, one tool at a time: home -> `tryOn` -> `capture(.desired)` -> `lookBrief` -> `recommendedTutorial`
/// -> `capture(.result)` -> `feedback` -> home.
enum AppRoute: Hashable {
    /// Try On for the one tool picked on the home screen.
    case tryOn(TryOnTool)
    /// A photo with the face feature inside the frame: the desired look (makeup preview on) or the result (plain camera).
    case capture(CaptureStage, TutorialHandoff)
    /// The desired-look photo, the style and what to prepare, then "Go to Tutorial".
    case lookBrief(TutorialHandoff)
    // -Nimah: The tutorial receives every tool's shade/strength from its preceding try-on.
    /// `attempt` changes when the feedback screen sends the user back, so the tutorial restarts from its first step.
    case recommendedTutorial(TutorialHandoff, attempt: Int = 0)
    /// Loading while the photos are compared, then the feedback.
    case feedback(TutorialHandoff)
    /// -Nimah: a saved look from My Looks, read only, with Try again.
    case myLook(UUID)
    /// -Nimah: the My Looks page: every saved look, favourites, rename, redo and delete.
    case myLooks
}

/// Which photo the capture screen takes.
enum CaptureStage: Hashable {
    /// Right after Try On, with the chosen look drawn: what the result is compared against.
    case desired
    /// After the tutorial, with the real makeup on and nothing drawn.
    case result
}
