import Foundation

struct ShapeWeight: Hashable, Sendable {
    let shape: FaceShape
    let weight: Double
}

// -Nimah: Hanum eyeliner plan only; brow/blush preferences live in Nimah studio.
struct MakeupPlan: Hashable, Sendable {
    static let personalPrefix = "personal."

    /// The shape whose catalog styles and reasons are shown.
    let shape: FaceShape
    /// Shapes mixed into the made-for-you styles, strongest first; weights sum to 1.
    let blend: [ShapeWeight]
    /// The eye measurements from the face scan; the eyeliner follows these, not the face shape. `nil` when the
    /// scan has none (an older scan, or the eyes could not be read).
    let eyes: EyeScan?
    /// Grouped by category in `MakeupCategory.allCases` order, made-for-you first in each category.
    let recommendations: [MakeupRecommendation]

    /// - Parameter chosenShape: a shape the user picked instead of the scanned one. The made-for-you styles then
    ///   use only that shape, still tuned to the scanned proportions.
    init(scan: FaceShapeResult, chosenShape: FaceShape? = nil, eyeScan:EyeShapeResult? = nil) {
        let blend = chosenShape.map { [ShapeWeight(shape: $0, weight: 1)] } ?? Self.blend(of: scan)
        self.init(shape: chosenShape ?? scan.shape, blend: blend, deviation: scan.deviation,
                  eyes: eyeScan == nil ? scan.eyes : eyeScan.flatMap(Self.savedEyeMeasurements))
    }

    /// A plan for a shape alone, without scan measurements.
    init(shape: FaceShape, eyeScan:EyeShapeResult? = nil) {
        self.init(shape: shape, blend: [ShapeWeight(shape: shape, weight: 1)],
                  deviation: FaceProportions(length: 0, forehead: 0, jaw: 0, chin: 0), eyes: eyeScan.flatMap(Self.savedEyeMeasurements))
    }

    // -Nimah: Adapt saved Khalish eye measurements to Hanum's planner without changing its formulas.
    // Units agree: opening/width, inner-corner gap/width and tilt degrees. Sample count is not
    // stored in EyeShapeResult; zero means unknown and is not used by the planner's confidence gate.
    static func savedEyeMeasurements(_ result:EyeShapeResult)->EyeScan? {
        let m=result.measurements
        guard result.confidence.isFinite,result.confidence>0.1,
              [m.tilt,m.spacing,m.openness].allSatisfy({ $0.isFinite }),m.spacing>0,m.openness>0 else { return nil }
        let lid:LidType = result.lid == .hooded ? .hooded : (result.lid == .monolid ? .monolid : .neither)
        return EyeScan(tiltLeft:m.tilt,tiltRight:m.tilt,spacing:m.spacing,openness:m.openness,samples:0,lidType:lid)
    }

    private init(shape: FaceShape, blend: [ShapeWeight], deviation: FaceProportions, eyes: EyeScan?) {
        self.shape = shape
        self.blend = blend
        self.eyes = eyes
        // -Nimah: This plan is eyeliner-only. Nimah's studio owns eyebrow/blush preferences.
        // -Nimah: One eye-scan assignment only; catalog variants stay internal to Hanum’s planner.
        recommendations = [MakeupPersonalizer.eyeliner(eyes)]
    }

    func recommendations(in category: MakeupCategory) -> [MakeupRecommendation] {
        recommendations.filter { $0.category == category }
    }

    var madeForYou: [MakeupRecommendation] { recommendations.filter(Self.isMadeForYou) }

    /// The made-for-you eyeliner and why; it depends on the eyes only.
    var eyeliner: EyelinerPlan { EyelinerPlanner.plan(for: eyes) }

    func reason(for category: MakeupCategory) -> LocalizedStringResource {
        category == .eyeliner ? eyeliner.reason : MakeupRecommender.reason(for: shape, category: category)
    }

    static func isMadeForYou(_ recommendation: MakeupRecommendation) -> Bool {
        recommendation.id.hasPrefix(personalPrefix)
    }

    /// Up to three closest shapes scoring at least 10%, renormalised. The top shape is always included.
    static func blend(of scan: FaceShapeResult) -> [ShapeWeight] {
        let ranked = scan.rankedShapes
        let kept = ranked.prefix(3).enumerated().filter { $0.offset == 0 || $0.element.score >= 0.1 }.map(\.element)
        let total = kept.reduce(0) { $0 + $1.score }
        guard total > 0 else { return [ShapeWeight(shape: scan.shape, weight: 1)] }
        return kept.map { ShapeWeight(shape: $0.shape, weight: $0.score / total) }
    }
}

/// Builds the made-for-you eyeliner from eye shape (`EyelinerPlanner`).
// -Nimah: Removed Khalish eyebrow/blush blending rules; retained Hanum eye-shape planning.
enum MakeupPersonalizer {
    static func eyeliner(_ eyes: EyeScan?) -> MakeupRecommendation {
        let plan = EyelinerPlanner.plan(for: eyes)
        let shapes = plan.blend.map { "\($0.shape.rawValue)\(Int(($0.weight * 100).rounded()))" }
        return MakeupRecommendation(
            id: MakeupPlan.personalPrefix + MakeupCategory.eyeliner.rawValue + "."
                + (shapes.isEmpty ? "neutral" : shapes.joined(separator: "-")),
            name: "Made for you", detail: "Line weight, start and wing chosen from your eye shape.",
            style: .eyeliner(plan.style))
    }

}
