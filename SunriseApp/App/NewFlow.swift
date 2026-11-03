import Foundation

/// The guided flow being built (splash, onboarding, compact opening, comparison, preparation, feedback) stays behind this
/// switch until its screens are designed, so the app on everyone's phone is unchanged. Turn it on with developer tools
/// (long-press the logo on Try On), then "New flow". The entry screens show from the next launch; the screens after Try
/// On show at once.
enum NewFlow {
    static let key = "dandan.newFlow"
}
