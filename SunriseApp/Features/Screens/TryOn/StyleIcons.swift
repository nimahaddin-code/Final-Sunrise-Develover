import SwiftUI

/// Little drawn faces for the brow and blush pickers: a peach disc with the part of the face the style changes.
/// Drawn, not photographs: they show the shape of each style.
enum StylePalette {
    static let skin = Color(red: 0xF3 / 255, green: 0xCB / 255, blue: 0xA6 / 255)
    static let brow = Color(red: 0x5A / 255, green: 0x3A / 255, blue: 0x28 / 255)
    static let blush = Color(red: 0xF5 / 255, green: 0x47 / 255, blue: 0x7D / 255)
}

/// A peach disc with an eye and the brow picture above it.
struct BrowStyleIcon: View {
    let assetName: String

    var body: some View {
        Canvas { context, size in
            let eye = CGRect(x: size.width * 0.26, y: size.height * 0.52, width: size.width * 0.48, height: size.height * 0.2)
            var almond = Path()
            almond.move(to: CGPoint(x: eye.minX, y: eye.midY))
            almond.addQuadCurve(to: CGPoint(x: eye.maxX, y: eye.midY), control: CGPoint(x: eye.midX, y: eye.minY - eye.height * 0.5))
            almond.addQuadCurve(to: CGPoint(x: eye.minX, y: eye.midY), control: CGPoint(x: eye.midX, y: eye.maxY + eye.height * 0.5))
            context.fill(almond, with: .color(.white))
            context.stroke(almond, with: .color(StylePalette.brow.opacity(0.7)), lineWidth: 0.8)
            let iris = size.width * 0.17
            context.fill(Path(ellipseIn: CGRect(x: eye.midX - iris / 2, y: eye.midY - iris / 2, width: iris, height: iris)),
                         with: .color(StylePalette.brow))
        }
        .overlay(alignment: .top) {
            GeometryReader { geo in
                Image(assetName).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(StylePalette.brow)
                    .frame(width: geo.size.width * 0.78, height: geo.size.height * 0.3)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.36)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A peach disc with a face in three-quarter view (looking left: brow, eye, nose, lips, hair at the right) and the blush of
/// one look on the cheek, after the design's look pictures (2026-11-13).
struct BlushStyleIcon: View {
    let look: BlushPlacementStyle

    /// Centre (fractions of the disc), size and tilt (degrees, negative = rising to the right) of the blush patch.
    var patch: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, tilt: CGFloat) {
        switch look {
        case .cheekboneLook: (0.62, 0.6, 0.46, 0.17, -28)
        case .appleLook: (0.5, 0.64, 0.3, 0.28, 0)
        case .sunkissed: (0.4, 0.56, 0.96, 0.18, 0)
        case .lifted: (0.68, 0.5, 0.42, 0.16, -55)
        case .softSweep: (0.6, 0.65, 0.5, 0.2, -6)
        default: (0.52, 0.64, 0.38, 0.3, 0)
        }
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            let p = patch
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: w * 0.06))
                var blob = Path(ellipseIn: CGRect(x: -p.w * w / 2, y: -p.h * h / 2, width: p.w * w, height: p.h * h))
                blob = blob.applying(CGAffineTransform(rotationAngle: p.tilt * .pi / 180))
                    .applying(CGAffineTransform(translationX: p.x * w, y: p.y * h))
                layer.fill(blob, with: .color(StylePalette.blush.opacity(0.8)))
            }
            // Hair along the right edge.
            var hair = Path()
            hair.move(to: pt(0.8, 0))
            hair.addQuadCurve(to: pt(0.86, 0.62), control: pt(0.92, 0.3))
            hair.addQuadCurve(to: pt(0.78, 1), control: pt(0.8, 0.82))
            hair.addLine(to: pt(1, 1)); hair.addLine(to: pt(1, 0)); hair.closeSubpath()
            context.fill(hair, with: .color(StylePalette.brow.opacity(0.85)))
            // Brow and eye.
            var brow = Path()
            brow.move(to: pt(0.34, 0.3))
            brow.addQuadCurve(to: pt(0.7, 0.29), control: pt(0.52, 0.2))
            context.stroke(brow, with: .color(StylePalette.brow), style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round))
            var eye = Path()
            eye.move(to: pt(0.38, 0.41))
            eye.addQuadCurve(to: pt(0.64, 0.41), control: pt(0.51, 0.31))
            eye.addQuadCurve(to: pt(0.38, 0.41), control: pt(0.51, 0.48))
            context.fill(eye, with: .color(.white))
            let iris = w * 0.1
            context.fill(Path(ellipseIn: CGRect(x: 0.5 * w - iris / 2, y: 0.4 * h - iris / 2, width: iris, height: iris)),
                         with: .color(StylePalette.brow))
            context.stroke(eye, with: .color(StylePalette.brow.opacity(0.8)), lineWidth: 0.8)
            // Nose line and lips, toward the left edge.
            var nose = Path()
            nose.move(to: pt(0.24, 0.4))
            nose.addQuadCurve(to: pt(0.15, 0.6), control: pt(0.2, 0.52))
            nose.addQuadCurve(to: pt(0.26, 0.63), control: pt(0.18, 0.66))
            context.stroke(nose, with: .color(StylePalette.brow.opacity(0.55)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            var lips = Path()
            lips.move(to: pt(0.17, 0.78))
            lips.addQuadCurve(to: pt(0.36, 0.78), control: pt(0.27, 0.72))
            lips.addQuadCurve(to: pt(0.17, 0.78), control: pt(0.27, 0.86))
            context.fill(lips, with: .color(Color(red: 0.78, green: 0.5, blue: 0.48)))
        }
        .accessibilityHidden(true)
    }
}
