/// Face proportions relative to the cheekbone width, so they do not depend on head size or camera distance.
struct FaceProportions: Equatable, Codable, Sendable {
    /// Face length divided by cheekbone width.
    var length: Float
    /// Forehead width divided by cheekbone width.
    var forehead: Float
    /// Jaw width divided by cheekbone width.
    var jaw: Float
    /// Chin width divided by jaw width; low values mean a pointed chin, high values a square one.
    var chin: Float
}

/// Collects per-frame proportions and reports the per-component median, which ignores occasional bad frames.
struct FaceProportionsSampler {
    let requiredSamples: Int
    private(set) var samples: [FaceProportions] = []

    init(requiredSamples: Int) { self.requiredSamples = max(1, requiredSamples) }

    var progress: Double { min(1, Double(samples.count) / Double(requiredSamples)) }
    var isComplete: Bool { samples.count >= requiredSamples }

    mutating func add(_ proportions: FaceProportions) {
        guard !isComplete else { return }
        samples.append(proportions)
    }

    mutating func reset() { samples.removeAll() }

    func median() -> FaceProportions? {
        guard !samples.isEmpty else { return nil }
        func middle(_ value: (FaceProportions) -> Float) -> Float {
            let sorted = samples.map(value).sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        return FaceProportions(length: middle(\.length), forehead: middle(\.forehead),
                               jaw: middle(\.jaw), chin: middle(\.chin))
    }
}
