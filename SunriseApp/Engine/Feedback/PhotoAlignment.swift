// -Nimah: lines the result photo up with the bare "Before" photo for the feedback's slider, so the divider cuts both faces
// at the same place. Uses the eye centres recorded at each shutter: the After picture is moved, scaled and turned so its
// eyes land on the Before picture's eyes. Memory only.
import CoreGraphics
import UIKit

enum PhotoAlignment {
    /// The similarity transform (move, scale, turn) that takes `from` eyes onto `to` eyes. Nil for eyes on one spot.
    static func transform(from: (CGPoint, CGPoint), to: (CGPoint, CGPoint)) -> CGAffineTransform? {
        let a = CGVector(dx: from.1.x - from.0.x, dy: from.1.y - from.0.y)
        let b = CGVector(dx: to.1.x - to.0.x, dy: to.1.y - to.0.y)
        let la = hypot(a.dx, a.dy), lb = hypot(b.dx, b.dy)
        guard la > 1, lb > 1 else { return nil }
        let scale = lb / la, angle = atan2(b.dy, b.dx) - atan2(a.dy, a.dx)
        // Move `from.0` to the origin, scale and turn, then move it onto `to.0`.
        return CGAffineTransform(translationX: -from.0.x, y: -from.0.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: to.0.x, y: to.0.y))
    }

    /// `after` redrawn in `before`'s frame with its eyes on `before`'s eyes, or `after` unchanged when the eyes are unknown
    /// or the move would be implausible (more than 1.6x larger or smaller, or turned more than 25°).
    static func align(after: UIImage, afterScan: FaceScan?, to before: UIImage, beforeScan: FaceScan?) -> UIImage {
        guard let afterScan, let beforeScan,
              let al = afterScan.leftEye, let ar = afterScan.rightEye, let bl = beforeScan.leftEye, let br = beforeScan.rightEye,
              afterScan.viewport.width > 0, beforeScan.viewport.width > 0 else { return after }
        // Eye points are in each camera view's points; the photos are those views at their own size.
        func image(_ p: CGPoint, _ scan: FaceScan, _ picture: UIImage) -> CGPoint {
            CGPoint(x: p.x / scan.viewport.width * picture.size.width, y: p.y / scan.viewport.height * picture.size.height)
        }
        let from = (image(al, afterScan, after), image(ar, afterScan, after))
        let to = (image(bl, beforeScan, before), image(br, beforeScan, before))
        guard let t = transform(from: from, to: to) else { return after }
        let scale = hypot(t.a, t.b), angle = abs(atan2(t.b, t.a)) * 180 / .pi
        guard scale > 1 / 1.6, scale < 1.6, angle < 25 else { return after }
        let format = UIGraphicsImageRendererFormat(for: before.traitCollection)
        return UIGraphicsImageRenderer(size: before.size, format: format).image { context in
            // The unmoved picture underneath fills the corners the move leaves empty.
            after.draw(in: CGRect(origin: .zero, size: before.size))
            context.cgContext.concatenate(t)
            after.draw(at: .zero)
        }
    }
}
