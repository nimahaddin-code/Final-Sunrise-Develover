// -Nimah: Shared integration preserves all team tabs.
enum AppTab: Hashable { case tryOn, discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    // -Nimah: Eyebrow module memakai sesi AR foundation aplikasi yang sama.
    case eyebrowGuide
    case referenceImport
    case session(MakeupReference)
    case savedLookDetail(SavedLookMetadata)
    case makeupTryOn(plan: MakeupPlan, applied: [MakeupRecommendation])
    case faceScan
}
