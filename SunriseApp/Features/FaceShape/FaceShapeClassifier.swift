import Foundation

struct FaceShapeResult: Equatable, Codable, Sendable {
    let shape: FaceShape
    let runnerUp: FaceShape
    /// Share of the score that went to `shape`, from 0 to 1.
    let confidence: Double
    /// Scores for every shape, summing to 1.
    let scores: [FaceShape: Double]
    /// Measured proportions as a fraction above or below the reference face, e.g. 0.05 = 5% larger.
    let deviation: FaceProportions
    /// Camera frames whose Vision face outline refined the mesh measurements; 0 means mesh only.
    var contourSamples = 0

    var rankedShapes: [(shape: FaceShape, score: Double)] {
        FaceShape.allCases.map { ($0, scores[$0] ?? 0) }.sorted { $0.score > $1.score }
    }
}

/// Compares measured proportions with a reference face (ARKit's neutral mesh) and scores each shape
/// by distance to a prototype. Prototypes are expressed in `unit`s of relative deviation from the reference.
///
/// The ARKit mesh only adapts partly to a person's face, so differences are small; tune `unit` on real devices.
struct FaceShapeClassifier: Sendable {
    let reference: FaceProportions
    var unit: Float = 0.04
    var temperature: Float = 1
    var prototypes = FaceShapeClassifier.prototypes

    /// (length, forehead, jaw, chin) in units of deviation from the reference face.
    static let prototypes: [FaceShape: SIMD4<Float>] = [
        .oval: SIMD4(0.3, 0, -0.3, 0),
        .round: SIMD4(-1, 0, 0, -0.3),
        .square: SIMD4(-0.7, 0.5, 1, 1),
        .oblong: SIMD4(1.2, 0.3, 0.3, 0.3),
        .heart: SIMD4(0, 1, -1, -1),
        .diamond: SIMD4(0.3, -1, -1, -0.5),
        .triangle: SIMD4(0, -1, 1, 0.5),
    ]

    func deviation(of proportions: FaceProportions) -> FaceProportions {
        FaceProportions(length: proportions.length / reference.length - 1,
                        forehead: proportions.forehead / reference.forehead - 1,
                        jaw: proportions.jaw / reference.jaw - 1,
                        chin: proportions.chin / reference.chin - 1)
    }

    func classify(_ proportions: FaceProportions) -> FaceShapeResult {
        let deviation = deviation(of: proportions)
        let point = SIMD4(deviation.length, deviation.forehead, deviation.jaw, deviation.chin) / unit

        var weights: [FaceShape: Double] = [:]
        for shape in FaceShape.allCases {
            let difference = point - (prototypes[shape] ?? .zero)
            let squaredDistance = (difference * difference).sum()
            weights[shape] = exp(-Double(squaredDistance / temperature))
        }
        let total = weights.values.reduce(0, +)
        let scores = weights.mapValues { total > 0 ? $0 / total : 1 / Double(FaceShape.allCases.count) }

        let ranked = FaceShape.allCases.sorted { (scores[$0] ?? 0) > (scores[$1] ?? 0) }
        return FaceShapeResult(shape: ranked[0], runnerUp: ranked[1], confidence: scores[ranked[0]] ?? 0,
                               scores: scores, deviation: deviation)
    }
}
