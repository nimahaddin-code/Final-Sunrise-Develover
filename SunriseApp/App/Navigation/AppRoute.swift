// -Nimah: AppRoute.swift — implementasi MVP SunriseApp.
enum AppTab: Hashable { case discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    case referenceImport
    case session(MakeupReference)
    case savedLookDetail(SavedLookMetadata)
}
