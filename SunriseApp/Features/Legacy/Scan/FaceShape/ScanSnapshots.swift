import CoreImage
import ImageIO
import UIKit

/// The one still taken from each scan (face, eyes), kept on this device so the profile can show it again.
/// Written as a small JPEG in Application Support, left out of backups and never uploaded. A new scan replaces it.
enum ScanSnapshots {
    enum Kind: String, CaseIterable { case face, eyes }

    /// Longest side of the stored image, in pixels; enough for a profile portrait without keeping a full frame.
    static let maxPixels: CGFloat = 720

    private static let context = CIContext()

    static func load(_ kind: Kind) -> UIImage? {
        UIImage(contentsOfFile: url(for: kind).path)
    }

    static func remove(_ kind: Kind) {
        try? FileManager.default.removeItem(at: url(for: kind))
    }

    /// Renders, crops and stores one camera frame. Call off the main actor; it blocks while rendering.
    /// - Parameters:
    ///   - orientation: how to turn the buffer upright.
    ///   - crop: region of the upright image to keep, in pixels with a top-left origin; the whole frame when `nil`.
    @discardableResult
    static func save(_ source: SendablePixelBuffer, orientation: CGImagePropertyOrientation = .up,
                     crop: CGRect? = nil, as kind: Kind) -> Bool {
        var image = CIImage(cvPixelBuffer: source.buffer).oriented(orientation)
        let size = image.extent
        if let crop {
            // Core Image's origin is bottom-left.
            let flipped = CGRect(x: crop.minX, y: size.height - crop.maxY, width: crop.width, height: crop.height)
                .intersection(size)
            guard !flipped.isNull, flipped.width > 1, flipped.height > 1 else { return false }
            image = image.cropped(to: flipped)
        }
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxPixels {
            let scale = maxPixels / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cgImage = context.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else { return false }
        return write(data, to: url(for: kind))
    }

    /// A rectangle around both eyes and brows, `aspect` wide per unit of height, clamped to the frame.
    static func eyeCrop(_ landmarks: EyeScanLandmarks, imageSize: CGSize, aspect: CGFloat = 2.1) -> CGRect? {
        let points = [landmarks.first, landmarks.second].flatMap { $0.lid + $0.brow + $0.iris }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let center = CGPoint(x: CGFloat(minX + maxX) / 2, y: CGFloat(minY + maxY) / 2)
        var width = CGFloat(maxX - minX) * 1.5
        var height = width / aspect
        // Keep the box inside the frame at this aspect.
        let scale = min(1, imageSize.width / width, imageSize.height / height)
        width *= scale; height *= scale
        let x = min(max(center.x - width / 2, 0), imageSize.width - width)
        let y = min(max(center.y - height / 2, 0), imageSize.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func url(for kind: Kind) -> URL {
        directory.appendingPathComponent("\(kind.rawValue).jpg")
    }

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScanSnapshots", isDirectory: true)
    }

    private static func write(_ data: Data, to url: URL) -> Bool {
        do {
            var directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
