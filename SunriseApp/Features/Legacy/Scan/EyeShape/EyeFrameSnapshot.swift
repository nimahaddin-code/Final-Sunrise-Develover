import CoreImage
import CoreVideo

/// Makes the eye scan picture from a camera frame: mirrored like the preview, cropped around the eyes, with the lines on it.
/// Runs on the camera queue; the picture is only handed to the result screen and never stored.
enum EyeFrameSnapshot {
    /// One context for every frame; `CIContext` is safe to share between threads.
    private static let context = CIContext()

    /// `landmarks` must come from this very `buffer`, upright BGRA.
    static func make(from buffer: CVPixelBuffer, landmarks: EyeScanLandmarks) -> ScanSnapshot? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let overlay = EyeOverlay.overlay(for: landmarks, imageSize: SIMD2(Float(width), Float(height))),
              let bounds = overlay.bounds, bounds.width > 0, bounds.height > 0 else { return nil }

        // Wide margin: the eyes alone would be a thin strip, and the brows sit above them.
        let focus = bounds.insetBy(dx: -bounds.width * 0.25, dy: -bounds.height * 0.6)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        // CoreImage counts rows from the bottom.
        let mirrored = CIImage(cvPixelBuffer: buffer).oriented(.upMirrored)
        let region = CGRect(x: focus.minX * CGFloat(width), y: (1 - focus.maxY) * CGFloat(height),
                            width: focus.width * CGFloat(width), height: focus.height * CGFloat(height))
            .integral.intersection(mirrored.extent)
        guard region.width >= 1, region.height >= 1 else { return nil }
        guard let image = context.createCGImage(mirrored.cropped(to: region), from: region) else { return nil }
        let actual = CGRect(x: region.minX / CGFloat(width), y: 1 - region.maxY / CGFloat(height),
                            width: region.width / CGFloat(width), height: region.height / CGFloat(height))
        return ScanSnapshot(croppedImage: image, overlay: overlay.remapped(to: actual))
    }
}
