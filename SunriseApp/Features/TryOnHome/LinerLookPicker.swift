import SwiftUI

/// Horizontal list of the eyeliner looks as small pictures of an eye wearing each one, like the brow pictures.
/// The first tile (no sign) is the liner off. The pictures are drawn, not photographs: they show the shape of each look.
struct LinerLookPicker: View {
    let selected: LinerLook?
    let onSelect: (LinerLook?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                tile(isSelected: selected == nil, label: Text("No eyeliner")) { onSelect(nil) } content: {
                    VStack(spacing: 4) {
                        Image(systemName: "nosign").font(.title2).frame(width: 96, height: 34)
                        Text("None").font(AppTypography.caption.weight(.semibold))
                    }
                }
                ForEach(LinerLook.allCases) { look in
                    tile(isSelected: selected == look, label: Text(look.title)) { onSelect(look) } content: {
                        VStack(spacing: 4) {
                            LinerLookThumbnail(look: look).frame(width: 96, height: 34)
                            Text(look.title).font(AppTypography.caption.weight(.semibold))
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func tile<Content: View>(isSelected: Bool, label: Text, action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(AppColors.snow)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppColors.flamingo.opacity(isSelected ? 0.32 : 0.16),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColors.snow, lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small eye, seen from the front, with the liner of one look on it.
struct LinerLookThumbnail: View {
    let look: LinerLook

    /// Fractions of the eye width: the wing's length and angle (degrees, up is positive), the thickest part of the line,
    /// how much of the lower lash line is lined, and how far the line reaches in from the inner corner.
    private struct Shape {
        var wing: CGFloat, angle: CGFloat, thickness: CGFloat, lower: CGFloat, inner: CGFloat = 0
    }

    private var shape: Shape {
        switch look {
        case .classic: Shape(wing: 0.22, angle: 8, thickness: 0.07, lower: 0)
        case .cat: Shape(wing: 0.40, angle: 22, thickness: 0.10, lower: 0)
        case .puppy: Shape(wing: 0.30, angle: -18, thickness: 0.09, lower: 0.4)
        case .foxy: Shape(wing: 0.44, angle: 26, thickness: 0.08, lower: 0.5, inner: 0.1)
        case .arabian: Shape(wing: 0.24, angle: 6, thickness: 0.09, lower: 1)
        case .natural: Shape(wing: 0, angle: 0, thickness: 0.04, lower: 0)
        }
    }

    var body: some View {
        Canvas { context, size in
            let look = shape
            let width = size.width * 0.58
            let inner = CGPoint(x: size.width * 0.5 - width / 2, y: size.height * 0.56)
            let outer = CGPoint(x: size.width * 0.5 + width / 2, y: size.height * 0.5)
            let lift = size.height * 0.5
            let control = CGPoint(x: (inner.x + outer.x) / 2, y: inner.y - lift)
            let lowerControl = CGPoint(x: control.x, y: inner.y + lift * 0.55)

            func point(_ t: CGFloat, control: CGPoint) -> CGPoint {
                let u = 1 - t
                return CGPoint(x: u * u * inner.x + 2 * u * t * control.x + t * t * outer.x,
                               y: u * u * inner.y + 2 * u * t * control.y + t * t * outer.y)
            }

            // The eye: an almond outline and an iris.
            var almond = Path()
            almond.move(to: inner)
            almond.addQuadCurve(to: outer, control: control)
            almond.addQuadCurve(to: inner, control: lowerControl)
            context.stroke(almond, with: .color(AppColors.snow.opacity(0.85)), lineWidth: 1.2)
            let iris = CGRect(x: control.x - 4.5, y: (inner.y + outer.y) / 2 - 7.5 + 2, width: 9, height: 9)
            context.fill(Path(ellipseIn: iris), with: .color(AppColors.snow.opacity(0.85)))

            // The liner above the lash line: thin at the inner corner, thickest at the outer one.
            let steps = 14
            let start = -look.inner
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for i in 0...steps {
                let t = start + (1 - start) * CGFloat(i) / CGFloat(steps)
                let base = point(max(t, 0), control: control)
                let along = max(t, 0)
                let thick = width * look.thickness * (0.35 + 0.65 * along * along)
                var p = base
                if t < 0 { p = CGPoint(x: inner.x + (outer.x - inner.x) * t, y: inner.y) }
                bottom.append(p)
                top.append(CGPoint(x: p.x, y: p.y - thick))
            }
            var liner = Path()
            liner.addLines(top)
            if look.wing > 0 {
                let radians = look.angle * .pi / 180
                let tip = CGPoint(x: outer.x + width * look.wing * cos(radians), y: outer.y - width * look.wing * sin(radians))
                liner.addLine(to: tip)
            }
            liner.addLines(bottom.reversed())
            liner.closeSubpath()
            context.fill(liner, with: .color(AppColors.snow))

            if look.lower > 0 {
                var lowerLine = Path()
                let from = look.lower >= 1 ? 0 : 1 - look.lower
                for i in 0...10 {
                    let t = from + (1 - from) * CGFloat(i) / 10
                    let p = point(t, control: lowerControl)
                    i == 0 ? lowerLine.move(to: p) : lowerLine.addLine(to: p)
                }
                context.stroke(lowerLine, with: .color(AppColors.snow), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
