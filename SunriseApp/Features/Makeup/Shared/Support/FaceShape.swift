// -Nimah: Obsolete blush tip removed; face-shape labels and descriptions retained.
import Foundation

enum FaceShape: String, CaseIterable, Identifiable, Codable, Sendable {
    case oval, round, square, oblong, heart, diamond, triangle

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .oval: "Oval"
        case .round: "Round"
        case .square: "Square"
        case .oblong: "Oblong"
        case .heart: "Heart"
        case .diamond: "Diamond"
        case .triangle: "Triangle"
        }
    }

    var symbol: String {
        switch self {
        case .oval: "oval.portrait"
        case .round: "circle"
        case .square: "square"
        case .oblong: "rectangle.portrait"
        case .heart: "heart"
        case .diamond: "diamond"
        case .triangle: "triangle"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .oval: "Balanced proportions: a little longer than wide, with a jaw slightly narrower than the forehead."
        case .round: "Length and width are similar, with full cheeks and a soft, rounded jawline."
        case .square: "Forehead, cheekbones and jaw are close in width, with a strong, angular jawline."
        case .oblong: "Noticeably longer than wide, with fairly straight sides."
        case .heart: "A wider forehead that tapers down to a narrow jaw and a pointed chin."
        case .diamond: "Cheekbones are the widest point, with a narrower forehead and jaw."
        case .triangle: "The jaw is wider than the forehead, giving a fuller lower face."
        }
    }

}
