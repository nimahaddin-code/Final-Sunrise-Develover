import Foundation

/// The lipstick shapes on Try On. All three follow the person's own lips; what changes is how far the colour reaches.
enum LipStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// The person's own lip line, filled edge to edge.
    case natural
    /// Drawn a little past the lip line in the middle, for fuller-looking lips.
    case full
    /// Colour in the middle of the lips that fades towards the edge.
    case gradient

    var id: Self { self }

    var title: String {
        switch self {
        case .natural: String(localized: "Natural")
        case .full: String(localized: "Full")
        case .gradient: String(localized: "Gradient")
        }
    }
}

extension MakeupPalette {
    /// Approximate sRGB previews, not measured product colours.
    static let lipShades = [
        MakeupShade(id: "lips.rosyNude", name: "Rosy Nude", red: 0.80, green: 0.45, blue: 0.46, opacity: 0.75),
        MakeupShade(id: "lips.coralPink", name: "Coral Pink", red: 0.93, green: 0.42, blue: 0.40, opacity: 0.75),
        MakeupShade(id: "lips.classicRed", name: "Classic Red", red: 0.78, green: 0.10, blue: 0.17, opacity: 0.75),
        MakeupShade(id: "lips.berry", name: "Berry", red: 0.58, green: 0.13, blue: 0.30, opacity: 0.75),
        MakeupShade(id: "lips.mocha", name: "Mocha", red: 0.52, green: 0.27, blue: 0.22, opacity: 0.75),
    ]
}
