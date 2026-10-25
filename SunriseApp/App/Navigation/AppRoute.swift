enum AppTab: Hashable { case tryOn, discover, myLooks, scanDebug }

enum AppRoute: Hashable {
    case scanDebug
    case referenceDetail(MakeupReference)
    // -Nimah: Eyebrow module memakai sesi AR foundation aplikasi yang sama.
    case eyebrowGuide
    // -Nimah: Dedicated Nimah region entry, fed by Khalish scan output.
    case browBlush(FaceGuideRegion)
    // -Nimah: The tutorial receives every tool's shade/strength from its preceding try-on.
    case recommendedTutorial(TutorialHandoff)
    case referenceImport
    case session(MakeupReference)
    case savedLookDetail(SavedLookMetadata)
    case makeupTryOn(plan: MakeupPlan, applied: [MakeupRecommendation])
    case faceScan
    case eyeScan
    /// Face scan followed straight by the eye scan, as in onboarding.
    case fullScan
    case profile
    case tutorial
}
