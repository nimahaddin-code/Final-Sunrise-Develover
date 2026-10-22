// -Nimah: Shared integration preserves all team tabs.
enum AppTab: Hashable { case tryOn, discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    // -Nimah: Eyebrow module memakai sesi AR foundation aplikasi yang sama.
    case eyebrowGuide
    // -Nimah: Dedicated Nimah region entry, fed by Khalish scan output.
    case browBlush(FaceGuideRegion)
    // -Nimah: The tutorial receives the exact shade/strength from its preceding try-on.
    case recommendedTutorial(FaceGuideRegion,MakeupShade?,Double)
    case referenceImport
    case session(MakeupReference)
    case savedLookDetail(SavedLookMetadata)
    case makeupTryOn(plan: MakeupPlan, applied: [MakeupRecommendation])
    case faceScan
    case eyeScan
    case profile
    case tutorial
}
