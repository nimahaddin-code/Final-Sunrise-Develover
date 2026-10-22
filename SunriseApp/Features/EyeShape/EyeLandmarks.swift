import simd

/// The eye landmarks of one face as plain 2D points, so measuring never depends on MediaPipe or the camera.
///
/// Points can be in any image coordinates (pixels, y up or down, mirrored or rolled); `EyeMeasurer` works out
/// the face's own axes from the points. The two eyes can come in either order.
struct EyeLandmarks: Equatable, Sendable {
    struct Eye: Equatable, Sendable {
        /// Corner next to the nose.
        var innerCorner: SIMD2<Float>
        /// Corner toward the temple.
        var outerCorner: SIMD2<Float>
        /// Every point on the lid outline, upper and lower lid together.
        var lid: [SIMD2<Float>]
        /// Points on the iris rim; the farthest pair gives the iris diameter.
        var iris: [SIMD2<Float>]
        /// The lower edge of the eyebrow above this eye.
        var brow: [SIMD2<Float>]
    }

    var first: Eye
    var second: Eye
}

extension EyeLandmarks {
    /// MediaPipe Face Landmarker topology (468 face points plus 10 iris points). "Right" and "left" are the
    /// person's own sides. A mirrored selfie only swaps which one is on the image's left, and the two eyes
    /// are measured the same either way. Check these indices against a real scan on a device.
    enum MeshIndex {
        struct Eye {
            let inner: Int, outer: Int
            let lid: [Int]
            let iris: [Int]
            let brow: [Int]
        }

        static let pointCount = 478
        static let personRight = Eye(
            inner: 133, outer: 33,
            lid: [246, 161, 160, 159, 158, 157, 173, 7, 163, 144, 145, 153, 154, 155],
            iris: [469, 470, 471, 472],
            brow: [46, 53, 52, 65, 55])
        static let personLeft = Eye(
            inner: 362, outer: 263,
            lid: [466, 388, 387, 386, 385, 384, 398, 249, 390, 373, 374, 380, 381, 382],
            iris: [474, 475, 476, 477],
            brow: [276, 283, 282, 295, 285])
    }

    /// Builds the landmarks from MediaPipe's normalized face mesh (x and y in 0...1). `imageSize` restores the
    /// image's aspect ratio, without which a wide image would stretch every ratio. `nil` unless all 478 points
    /// (including the iris) are present.
    init?(normalizedMesh points: [SIMD2<Float>], imageSize: SIMD2<Float>) {
        guard points.count >= MeshIndex.pointCount, imageSize.x > 0, imageSize.y > 0 else { return nil }
        func eye(_ index: MeshIndex.Eye) -> Eye {
            func pixel(_ i: Int) -> SIMD2<Float> { points[i] * imageSize }
            return Eye(innerCorner: pixel(index.inner), outerCorner: pixel(index.outer), lid: index.lid.map(pixel),
                       iris: index.iris.map(pixel), brow: index.brow.map(pixel))
        }
        self.init(first: eye(MeshIndex.personRight), second: eye(MeshIndex.personLeft))
    }
}
