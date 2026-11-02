import CoreGraphics

/// Lines drawn on top of a scan picture so the person can see what was measured. Every point is normalized to the
/// picture it belongs to: (0, 0) is its top-left corner and (1, 1) its bottom-right, so the drawing scales with the view.
struct ScanOverlay: Equatable, Sendable {
    struct Stroke: Equatable, Sendable {
        enum Style: Equatable, Sendable {
            /// The shape itself, such as the face outline or the rim of an eye.
            case outline
            /// A line that was measured, drawn dashed with a dot at each end.
            case measure
            /// Supporting detail, drawn thin.
            case guide
        }

        var points: [CGPoint]
        var style: Style
        var closed = false
        /// English text, localized when drawn. Shown at the middle of the stroke.
        var label: String?
    }

    var strokes: [Stroke]

    var allPoints: [CGPoint] { strokes.flatMap(\.points) }

    /// The smallest rectangle holding every point; `nil` when there are none.
    var bounds: CGRect? {
        let points = allPoints
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The same lines expressed relative to `rect`, which is a part of the original picture (also normalized).
    func remapped(to rect: CGRect) -> ScanOverlay {
        guard rect.width > 0, rect.height > 0 else { return self }
        var copy = self
        for index in copy.strokes.indices {
            copy.strokes[index].points = copy.strokes[index].points.map {
                CGPoint(x: ($0.x - rect.minX) / rect.width, y: ($0.y - rect.minY) / rect.height)
            }
        }
        return copy
    }
}

/// A scan picture with its lines. It only lives in memory, for the result screen: it is never saved, uploaded or put in
/// `FaceShapeStore`.
///
/// The image is a `CGImage`, which never changes once made, so passing it between queues is safe.
struct ScanSnapshot: @unchecked Sendable {
    let image: CGImage
    let overlay: ScanOverlay

    /// Crops to the part of `image` around the lines (`focus`, normalized and padded by `padding` of its size on every
    /// side) and moves the lines onto the cropped picture. Pass the full lines and the full picture.
    init?(image: CGImage, overlay: ScanOverlay, padding: CGFloat = 0.2) {
        guard let bounds = overlay.bounds, bounds.width > 0, bounds.height > 0 else { return nil }
        let focus = bounds.insetBy(dx: -bounds.width * padding, dy: -bounds.height * padding)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let pixels = CGRect(x: (focus.minX * width).rounded(.down), y: (focus.minY * height).rounded(.down),
                            width: (focus.width * width).rounded(.up), height: (focus.height * height).rounded(.up))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixels.width >= 1, pixels.height >= 1, let cropped = image.cropping(to: pixels) else { return nil }
        // Remap against the pixels actually cropped, which differ from `focus` by rounding.
        let actual = CGRect(x: pixels.minX / width, y: pixels.minY / height, width: pixels.width / width,
                            height: pixels.height / height)
        self.image = cropped
        self.overlay = overlay.remapped(to: actual)
    }

    /// For a picture that is already cropped to its lines.
    init(croppedImage: CGImage, overlay: ScanOverlay) {
        image = croppedImage
        self.overlay = overlay
    }
}
