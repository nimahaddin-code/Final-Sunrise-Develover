enum AppTab: Hashable { case tryOn, discover, myLooks }

enum AppRoute: Hashable {
    case tryOn(TryOnTool)
    // -Nimah: The tutorial receives every tool's shade/strength from its preceding try-on.
    case recommendedTutorial(TutorialHandoff)
}
