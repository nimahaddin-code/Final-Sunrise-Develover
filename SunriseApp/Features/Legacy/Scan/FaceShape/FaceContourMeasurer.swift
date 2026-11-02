import simd

/// 2D coordinate frame of the face in the camera image: `x` across the face, `y` from chin toward forehead.
/// Built from the ARKit face pose so Vision's outline and the projected mesh are measured along the same axes.
struct FaceFrame2D: Equatable, Sendable {
    let origin: SIMD2<Float>
    let xAxis: SIMD2<Float>
    let yAxis: SIMD2<Float>

    init?(origin: SIMD2<Float>, xTip: SIMD2<Float>, yTip: SIMD2<Float>) {
        let x = xTip - origin, y = yTip - origin
        guard simd_length(x) > 0, simd_length(y) > 0 else { return nil }
        self.origin = origin
        xAxis = simd_normalize(x)
        yAxis = simd_normalize(y)
    }

    /// Image pixel → (across, up) in pixels.
    func local(_ point: SIMD2<Float>) -> SIMD2<Float> {
        let offset = point - origin
        return SIMD2(simd_dot(offset, xAxis), simd_dot(offset, yAxis))
    }
}

/// Where the ARKit mesh's chin, jaw and cheekbone bands sit in the image, and how wide the mesh looks there.
struct MeshSilhouette: Equatable, Sendable {
    struct Band: Equatable, Sendable {
        /// Band centre along the face's up axis, in image pixels.
        let height: Float
        /// Mesh width across the face at that band, in image pixels.
        let meshWidth: Float
    }

    let frame: FaceFrame2D
    let chinHeight: Float
    let chin: Band
    let jaw: Band
    let cheekbones: Band
}

/// Ratio of the real face outline (Vision) to the ARKit mesh outline per band; 1.1 = the real face is 10% wider.
/// `nil` means Vision's outline did not reach that band.
struct ContourCorrection: Equatable, Sendable {
    static let plausibleRange: ClosedRange<Float> = 0.7...1.4

    var chin: Float?
    var jaw: Float?
    var cheekbones: Float?

    /// Rescales mesh proportions with the measured outline. Forehead and length are only rescaled through the
    /// cheekbone width they are divided by, because Vision's face contour does not cover the forehead.
    func applied(to proportions: FaceProportions) -> FaceProportions {
        let cheekbones = cheekbones ?? 1
        let jaw = jaw ?? cheekbones
        let chin = chin ?? jaw
        return FaceProportions(length: proportions.length / cheekbones,
                               forehead: proportions.forehead / cheekbones,
                               jaw: proportions.jaw * jaw / cheekbones,
                               chin: proportions.chin * chin / jaw)
    }

    /// Per-band median, ignoring samples where that band was missing.
    static func median(of corrections: [ContourCorrection]) -> ContourCorrection? {
        guard !corrections.isEmpty else { return nil }
        func middle(_ value: (ContourCorrection) -> Float?) -> Float? {
            let sorted = corrections.compactMap(value).sorted()
            guard !sorted.isEmpty else { return nil }
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        return ContourCorrection(chin: middle(\.chin), jaw: middle(\.jaw), cheekbones: middle(\.cheekbones))
    }
}

extension ContourCorrection {
    /// One line per band for the debug log: how many outlines reached the band and how much their ratios spread.
    /// A large spread means Vision's outline is noisy there, so the median is less trustworthy.
    static func report(of corrections: [ContourCorrection]) -> String {
        let bands: [(String, KeyPath<ContourCorrection, Float?>)] = [("chin", \.chin), ("jaw", \.jaw), ("cheekbones", \.cheekbones)]
        let median = ContourCorrection.median(of: corrections)
        let lines = bands.map { name, path -> String in
            let values = corrections.compactMap { $0[keyPath: path] }
            guard let low = values.min(), let high = values.max() else { return "\(name): no samples" }
            let mean = values.reduce(0, +) / Float(values.count)
            let deviation = (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(values.count)).squareRoot()
            return String(format: "%@: n=%d median=%.3f min=%.3f max=%.3f sd=%.3f", name, values.count,
                          median?[keyPath: path] ?? mean, low, high, deviation)
        }
        return "outlines=\(corrections.count)\n" + lines.joined(separator: "\n")
    }
}

enum FaceContourMeasurer {
    /// Locates the mesh bands in the image. `projected[i]` is the image position of `vertices[i]`.
    static func silhouette(vertices: [SIMD3<Float>], projected: [SIMD2<Float>], frame: FaceFrame2D) -> MeshSilhouette? {
        guard vertices.count == projected.count,
              let bottom = vertices.map(\.y).min(), let top = vertices.map(\.y).max(), top > bottom else { return nil }
        let local = projected.map(frame.local)

        func band(_ band: FaceMeshMeasurer.Band) -> MeshSilhouette.Band? {
            let low = bottom + band.lower * (top - bottom), high = bottom + band.upper * (top - bottom)
            let points = vertices.indices.filter { vertices[$0].y >= low && vertices[$0].y <= high }.map { local[$0] }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), maxX > minX else { return nil }
            return MeshSilhouette.Band(height: points.map(\.y).reduce(0, +) / Float(points.count), meshWidth: maxX - minX)
        }

        guard let lowest = vertices.indices.min(by: { vertices[$0].y < vertices[$1].y }),
              let chin = band(FaceMeshMeasurer.chinBand), let jaw = band(FaceMeshMeasurer.jawBand),
              let cheekbones = band(FaceMeshMeasurer.cheekboneBand) else { return nil }
        return MeshSilhouette(frame: frame, chinHeight: local[lowest].y, chin: chin, jaw: jaw, cheekbones: cheekbones)
    }

    /// Compares Vision's face contour (image pixels, in order around the face) with the mesh silhouette.
    /// Returns `nil` when the contour's chin is not where the mesh's chin is, which means the outline belongs to
    /// a different face or was mapped with the wrong image orientation.
    static func correction(contour: [SIMD2<Float>], silhouette: MeshSilhouette) -> ContourCorrection? {
        let local = contour.map(silhouette.frame.local)
        guard let contourChin = local.map(\.y).min() else { return nil }
        let faceSpan = silhouette.cheekbones.height - silhouette.chinHeight
        guard faceSpan > 0, abs(contourChin - silhouette.chinHeight) < 0.15 * faceSpan else { return nil }

        func ratio(_ band: MeshSilhouette.Band) -> Float? {
            guard let width = width(of: local, atHeight: band.height) else { return nil }
            let ratio = width / band.meshWidth
            return ContourCorrection.plausibleRange.contains(ratio) ? ratio : nil
        }
        let correction = ContourCorrection(chin: ratio(silhouette.chin), jaw: ratio(silhouette.jaw),
                                           cheekbones: ratio(silhouette.cheekbones))
        return correction.jaw == nil && correction.chin == nil ? nil : correction
    }

    /// Width of an open polyline (face-local points) where it crosses the horizontal line at `height`.
    static func width(of polyline: [SIMD2<Float>], atHeight height: Float) -> Float? {
        var crossings: [Float] = []
        for (a, b) in zip(polyline, polyline.dropFirst()) where min(a.y, b.y) <= height && height <= max(a.y, b.y) {
            crossings.append(a.y == b.y ? a.x : a.x + (height - a.y) / (b.y - a.y) * (b.x - a.x))
        }
        guard let minX = crossings.min(), let maxX = crossings.max(), maxX > minX else { return nil }
        return maxX - minX
    }
}
