import CoreGraphics

/// How the detector is told to rotate the camera image so the face is upright. Same cases and meaning as
/// `UIImage.Orientation` / `CGImagePropertyOrientation` for the rotations (mirroring never matters to a detector).
enum DetectorRotation: Equatable, CaseIterable {
    case up, right, left, down

    /// The rotation that puts the head's up direction, as it appears in the captured image, at the top.
    /// The front camera's buffer is landscape, so this is `.right` or `.left` in portrait.
    static func forHeadUp(_ up: CGPoint) -> DetectorRotation {
        if abs(up.y) >= abs(up.x) { return up.y <= 0 ? .up : .down }
        return up.x < 0 ? .right : .left
    }

    /// Size of the rotated (upright) image for a raw image of `raw`.
    func uprightSize(raw: CGSize) -> CGSize {
        switch self {
        case .up, .down: raw
        case .right, .left: CGSize(width: raw.height, height: raw.width)
        }
    }

    /// Maps a pixel of the upright (rotated) image back to the raw captured image.
    func rawPoint(fromUpright p: CGPoint, raw: CGSize) -> CGPoint {
        switch self {
        case .up: p
        case .right: CGPoint(x: p.y, y: raw.height - p.x)
        case .left: CGPoint(x: raw.width - p.y, y: p.x)
        case .down: CGPoint(x: raw.width - p.x, y: raw.height - p.y)
        }
    }
}

/// What the detector's normalized landmark coordinates are relative to. MediaPipe's documentation does not say
/// whether they follow the rotated input or the raw buffer, and the spike needed a debug switch for it, so it is
/// decided from the face itself: the eyes' axis must agree with the axis ARKit sees for the same frame.
enum LandmarkSpace: Equatable {
    case rawImage
    case rotatedImage

    /// - Parameters:
    ///   - leftEye, rightEye: the two eyes' inner corners as reported (normalized).
    ///   - expectedAxis: the head's left-right axis in raw image pixels, from ARKit (sign does not matter).
    ///   - previous: the last decision; only changed when the other reading agrees much better.
    static func choose(leftEye: CGPoint, rightEye: CGPoint, rotation: DetectorRotation, raw: CGSize,
                       expectedAxis: CGPoint, previous: LandmarkSpace?) -> LandmarkSpace {
        func agreement(_ space: LandmarkSpace) -> CGFloat {
            let a = rawPixel(leftEye, space: space, rotation: rotation, raw: raw)
            let b = rawPixel(rightEye, space: space, rotation: rotation, raw: raw)
            let axis = b - a
            guard axis.length > 1e-6, expectedAxis.length > 1e-6 else { return 0 }
            return abs(axis.normalized().dot(expectedAxis.normalized()))
        }
        let rawScore = agreement(.rawImage), rotatedScore = agreement(.rotatedImage)
        let better: LandmarkSpace = rotatedScore > rawScore ? .rotatedImage : .rawImage
        guard let previous, previous != better else { return better }
        let margin: CGFloat = 0.3
        return abs(rawScore - rotatedScore) > margin ? better : previous
    }

    /// A normalized landmark as a pixel of the raw captured image.
    static func rawPixel(_ normalized: CGPoint, space: LandmarkSpace, rotation: DetectorRotation,
                         raw: CGSize) -> CGPoint {
        switch space {
        case .rawImage:
            return CGPoint(x: normalized.x * raw.width, y: normalized.y * raw.height)
        case .rotatedImage:
            let upright = rotation.uprightSize(raw: raw)
            return rotation.rawPoint(fromUpright: CGPoint(x: normalized.x * upright.width, y: normalized.y * upright.height),
                                     raw: raw)
        }
    }
}
