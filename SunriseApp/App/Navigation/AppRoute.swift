// -Nimah: AppRoute.swift — implementasi MVP SunriseApp.
enum AppTab: Hashable { case discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    // -Nimah: Eyebrow module memakai sesi AR foundation aplikasi yang sama.
    case eyebrowGuide
    case referenceImport
    case session(MakeupReference)
    case savedLookDetail(SavedLookMetadata)
}
