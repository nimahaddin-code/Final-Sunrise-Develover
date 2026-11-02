/// Measures face proportions from face mesh vertices in face-local space (meters, +y up, +x sideways).
///
/// Works on plain vertices so it can be tested without ARKit. Bands are fractions of the mesh height measured
/// from the chin. The ARKit mesh stops at the upper forehead, so "length" is chin to mesh top, not to the hairline.
enum FaceMeshMeasurer {
    struct Band: Sendable {
        let lower: Float
        let upper: Float
    }

    static let chinBand = Band(lower: 0.04, upper: 0.10)
    static let jawBand = Band(lower: 0.18, upper: 0.26)
    static let cheekboneBand = Band(lower: 0.50, upper: 0.66)
    static let foreheadBand = Band(lower: 0.84, upper: 0.92)

    static func proportions(of vertices: [SIMD3<Float>]) -> FaceProportions? {
        guard let bottom = vertices.map(\.y).min(), let top = vertices.map(\.y).max() else { return nil }
        let length = top - bottom
        guard length > 0 else { return nil }

        func width(_ band: Band) -> Float? {
            let low = bottom + band.lower * length, high = bottom + band.upper * length
            let xs = vertices.lazy.filter { $0.y >= low && $0.y <= high }.map(\.x)
            guard let minX = xs.min(), let maxX = xs.max(), maxX > minX else { return nil }
            return maxX - minX
        }

        guard let chin = width(chinBand), let jaw = width(jawBand),
              let cheekbones = width(cheekboneBand), let forehead = width(foreheadBand) else { return nil }
        return FaceProportions(length: length / cheekbones, forehead: forehead / cheekbones,
                               jaw: jaw / cheekbones, chin: chin / jaw)
    }
}
