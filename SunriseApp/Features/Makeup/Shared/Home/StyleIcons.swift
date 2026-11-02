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

/// A peach disc with an eye, a nose and the blush of one look on the cheek.
struct BlushStyleIcon: View {
    let look: BlushPlacementStyle

    /// Centre (fractions of the disc), size and tilt (degrees) of the blush patch.
    private var patch: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, tilt: CGFloat) {
        switch look {
        case .sunkissed: (0.52, 0.64, 0.74, 0.22, 0)
        case .lifted: (0.62, 0.56, 0.5, 0.22, -28)
        default: (0.56, 0.64, 0.42, 0.34, 0)
        }
    }

    var body: some View {
        Canvas { context, size in
            let p = patch
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: size.width * 0.07))
                var blob = Path(ellipseIn: CGRect(x: -p.w * size.width / 2, y: -p.h * size.height / 2,
                                                  width: p.w * size.width, height: p.h * size.height))
                blob = blob.applying(CGAffineTransform(rotationAngle: p.tilt * .pi / 180))
                    .applying(CGAffineTransform(translationX: p.x * size.width, y: p.y * size.height))
                layer.fill(blob, with: .color(StylePalette.blush.opacity(0.85)))
            }
            var lid = Path()
            lid.move(to: CGPoint(x: size.width * 0.52, y: size.height * 0.4))
            lid.addQuadCurve(to: CGPoint(x: size.width * 0.8, y: size.height * 0.4),
                             control: CGPoint(x: size.width * 0.66, y: size.height * 0.3))
            context.stroke(lid, with: .color(StylePalette.brow), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
