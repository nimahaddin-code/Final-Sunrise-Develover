enum AppTab: Hashable { case tryOn, discover, myLooks }

enum AppRoute: Hashable {
    // -Nimah: The tutorial receives every tool's shade/strength from its preceding try-on.
    case recommendedTutorial(TutorialHandoff)
    // New flow (`NewFlow`): Try On -> comparison -> preparation -> tutorial -> feedback.
    case comparison(TutorialHandoff)
    case preparation(TutorialHandoff)
    case feedback(FeedbackInput)
}
