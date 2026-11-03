// -Nimah: Khalish eyebrow/blush recommendation catalog removed; Hanum eyeliner catalog retained.
import Foundation

enum MakeupRecommender {
    static func recommendations(for shape:FaceShape)->[MakeupRecommendation] { EyelinerPlanner.catalog }
    static func recommendations(for shape:FaceShape,in category:MakeupCategory)->[MakeupRecommendation] {
        category == .eyeliner ? EyelinerPlanner.catalog : []
    }
    static func reason(for shape:FaceShape,category:MakeupCategory)->LocalizedStringResource {
        category == .eyeliner ? "Chosen from your eye shape, not your face shape." : "Open Eyebrow & Blush Studio for placement preferences."
    }
}
