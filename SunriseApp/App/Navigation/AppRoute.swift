enum AppTab: Hashable { case tryOn, discover, myLooks }

enum AppRoute: Hashable {
    case referenceDetail(MakeupReference)
    case referenceImport
    case faceCalibration(referenceID: String)
    case tutorial(referenceID: String)
    case liveGuide(referenceID: String)
    case comparison(referenceID: String)
    case savedLookDetail(SavedLookMetadata)
    case makeupTryOn(plan: MakeupPlan, applied: [MakeupRecommendation])
    case faceScan
    case eyeScan
}
