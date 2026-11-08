import Foundation

/// The entry screens being built (splash, onboarding pages, compact opening) stay behind this switch until they are
/// designed. Turn it on with developer tools (long-press the logo on Try On), then "New flow"; they show from the next
/// launch. The screens after Try On (photo, brief, tutorial, photo, feedback) are always on.
enum NewFlow {
    static let key = "dandan.newFlow"
}
