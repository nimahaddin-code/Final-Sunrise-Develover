enum AppTab: Hashable { case discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    case referenceImport
    case faceCalibration(referenceID: String)
    case tutorial(referenceID: String)
    case liveGuide(referenceID: String)
    case comparison(referenceID: String)
    case savedLookDetail(SavedLookMetadata)
}
