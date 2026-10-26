import ActivityKit

/// The Live Activity shown in the Dynamic Island while a face or eye scan runs. Compiled into both the app and the
/// `SunriseLiveActivity` extension, so keep it free of anything the extension cannot import.
struct ScanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0 to 1.
        var progress: Double
        var isDone: Bool
    }

    /// "Face scan" or "Eye scan", already localized by the app.
    var title: String
}
