import SwiftUI

/// The language the app's own text is shown in, picked on the home screen. A choice is used at once and kept for the
/// next launch; until one is made, the app follows the language iOS picked for it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", indonesian = "id", chinese = "zh-Hans"

    static let key = "dandan.language"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Written in the language itself, so never translated.
    var name: String {
        switch self {
        case .english: "English"
        case .indonesian: "Bahasa Indonesia"
        case .chinese: "简体中文"
        }
    }

    /// The saved choice, or the language iOS picked for the app.
    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init)
            ?? Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init) ?? .english
    }

    /// This language's string tables (its `.lproj` folder in the app).
    var bundle: Bundle { Self.bundles[self] ?? .main }
    private static let bundles = Dictionary(uniqueKeysWithValues: allCases.compactMap { language in
        Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)).map { (language, $0) }
    })

    /// Saves the choice. `AppRootView` passes it to SwiftUI's `Text` (`\.locale`) and `String(localized:)` below reads
    /// it, so the screens change at once. `AppleLanguages` makes the next launch start in it too, for what iOS itself
    /// draws inside the app (permission prompts, the photo and colour pickers).
    func select() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}

/// `String(localized:)` with one argument, as the app writes it everywhere, resolves to these two inside the app, not to
/// Foundation's: Foundation's keeps the language the app was launched in, these follow the language chosen in the app.
extension String {
    init(localized value: String.LocalizationValue) {
        self.init(localized: value, table: nil, bundle: AppLanguage.current.bundle)
    }

    /// Disfavoured like Foundation's own, so a string literal means the one above.
    @_disfavoredOverload init(localized resource: LocalizedStringResource) {
        self.init(localized: resource.defaultValue, table: resource.table, bundle: AppLanguage.current.bundle)
    }
}
