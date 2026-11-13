import SwiftUI

/// Lips on the shared Try On screen: the lipstick shapes as little drawn lips; the first circle switches the lipstick
/// off. No debug menu.
struct LipsTryOnFeature: TryOnFeature {
    func lookPicker(home: TryOnHomeModel) -> AnyView {
        AnyView(
            LipStylePicker(selected: home.isOff ? nil : home.lipStyle) { style in
                if let style { home.setLipStyle(style) } else { home.turnOff() }
            }
        )
    }

    func styleName(home: TryOnHomeModel) -> Text {
        home.isOff ? Text("None") : Text(home.lipStyle.title)
    }
    var colourName: String { String(localized: "lipstick") }

    func debugMenu() -> AnyView? { nil }
}

/// The lipstick shapes as glass circles over the bottom of the camera, like the blush looks; the first circle is no
/// lipstick (`nil`).
struct LipStylePicker: View {
    /// The shape on the lips, nil when the lipstick is off.
    let selected: LipStyle?
    let onSelect: (LipStyle?) -> Void

    var body: some View {
        GlassPickerRow(selectedID: selected.map { "\($0.id)" } ?? "none", onCenter: { id in
            onSelect(LipStyle.allCases.first { "\($0.id)" == id })
        }) {
            Button { onSelect(nil) } label: {
                StyleCircle(selected: selected == nil, isNone: true) { EmptyView() }
            }
            .buttonStyle(.plain).id("none").accessibilityLabel("No lipstick")
            ForEach(LipStyle.allCases) { style in
                let isSelected = selected == style
                Button { onSelect(style) } label: {
                    StyleCircle(selected: isSelected) { LipStyleIcon(style: style) }
                }
                .buttonStyle(.plain)
                .id("\(style.id)")
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A peach disc with lips wearing one shape. Drawn, not a photograph: it shows how far the colour reaches.
struct LipStyleIcon: View {
    let style: LipStyle

    private static let lipstick = Color(red: 0xC9 / 255, green: 0x3A / 255, blue: 0x4E / 255)

    var body: some View {
        Canvas { context, size in
            // "Full" is the same mouth drawn a little taller and wider.
            let grow: CGSize = style == .full ? CGSize(width: 1.1, height: 1.3) : CGSize(width: 1, height: 1)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (0.5 + (x - 0.5) * grow.width) * size.width, y: (0.54 + (y - 0.54) * grow.height) * size.height)
            }
            let left = point(0.2, 0.54), right = point(0.8, 0.54)
            var lips = Path()
            lips.move(to: left)
            lips.addQuadCurve(to: point(0.41, 0.4), control: point(0.28, 0.42))
            lips.addQuadCurve(to: point(0.5, 0.44), control: point(0.46, 0.39))
            lips.addQuadCurve(to: point(0.59, 0.4), control: point(0.54, 0.39))
            lips.addQuadCurve(to: right, control: point(0.72, 0.42))
            lips.addQuadCurve(to: left, control: point(0.5, 0.86))
            lips.closeSubpath()
            if style == .gradient {
                context.fill(lips, with: .color(Self.lipstick.opacity(0.3)))
                context.drawLayer { layer in
                    layer.clip(to: lips)
                    layer.addFilter(.blur(radius: size.width * 0.06))
                    layer.fill(Path(ellipseIn: CGRect(x: size.width * 0.34, y: size.height * 0.46, width: size.width * 0.32,
                                                      height: size.height * 0.18)), with: .color(Self.lipstick))
                }
            } else {
                context.fill(lips, with: .color(Self.lipstick))
            }
            // The line where the lips meet.
            var line = Path()
            line.move(to: left)
            line.addQuadCurve(to: right, control: point(0.5, 0.6))
            context.stroke(line, with: .color(StylePalette.brow.opacity(0.55)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
