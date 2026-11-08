import SwiftUI

/// Native Liquid Glass building blocks for the camera screens (iOS 26). Nothing here is an image: the glass material,
/// its rim, highlight and touch response all come from `glassEffect`. Controls are tinted with the app's colours so they
/// stay readable over the camera picture.
extension View {
    /// Round glass surface. `tint` colours it (the chosen state); `nil` is the standard smoky glass of the app.
    func glassCircle(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(GlassStyle.make(tint: tint ?? AppColors.glassBase, interactive: interactive), in: .circle)
    }

    /// Capsule glass surface for labels, toggles and the selected tool.
    func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(GlassStyle.make(tint: tint ?? AppColors.glassBase, interactive: interactive), in: .capsule)
    }
}

private enum GlassStyle {
    static func make(tint: Color, interactive: Bool) -> Glass {
        let glass = Glass.regular.tint(tint)
        return interactive ? glass.interactive() : glass
    }
}

/// A round glass button with an SF Symbol: the tutorial arrow, the camera bar's compare and light buttons, back buttons.
struct GlassCircleButton: View {
    var symbol: String
    var size: CGFloat = 56
    var tint: Color?
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(AppColors.snow)
                .frame(width: size, height: size)
                .glassCircle(tint: tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Round pick button of the Try On pickers. The chosen one is larger and tinted, its icon in white.
struct GlassChoiceCircle<Content: View>: View {
    let selected: Bool
    var size: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        let side = size ?? (selected ? 46 : 36)
        content()
            .foregroundStyle(selected ? AppColors.snow : AppColors.cocoa)
            .frame(width: side, height: side)
            .glassCircle(tint: selected ? AppColors.glassSelected : AppColors.glassPale)
            .animation(.smooth(duration: 0.25), value: selected)
    }
}

/// Round pick of the brow and blush pickers, as in the design: a peach disc with a little drawing, the chosen one larger
/// with a white ring. `content == nil` is the "none" circle: grey glass with a slashed circle.
struct StyleCircle<Content: View>: View {
    let selected: Bool
    var isNone = false
    /// Size of the chosen circle when the picker magnifies it (brow); nil keeps every circle at 40.
    var selectedSide: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        let side: CGFloat = selected ? (selectedSide ?? 40) : 40
        ZStack {
            if isNone {
                Image(systemName: "nosign").font(.system(size: 20, weight: .regular)).foregroundStyle(AppColors.snow)
                    .frame(width: side, height: side)
                    .glassCircle(tint: Color.gray.opacity(0.55))
            } else {
                content().frame(width: side, height: side)
                    .background(StylePalette.skin, in: Circle())
                    .clipShape(Circle())
            }
        }
        .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: selectedSide == nil ? 2 : 3).opacity(selected ? 1 : 0))
        .frame(width: side, height: side)
        .animation(.smooth(duration: 0.25), value: selected)
    }
}

/// A label over a sideways row of `StyleCircle`s that works like an Instagram story filter strip: the circle in the
/// middle is the chosen one. Scrolling snaps a circle to the middle and chooses it (`onCenter` gets its id); tapping a
/// circle scrolls it to the middle. Each item gives itself `.id(...)`, equal to `selectedID` when chosen.
struct GlassPickerRow<Content: View>: View {
    let title: Text
    let selectedID: String
    var onCenter: (String) -> Void = { _ in }
    /// Height of the row; taller when the chosen circle is magnified.
    var rowHeight: CGFloat = 48
    /// Width of the chosen circle, so the first and last ones can sit exactly in the middle.
    var selectedWidth: CGFloat = 40
    @ViewBuilder var content: () -> Content
    @State private var position: String?

    var body: some View {
        VStack(spacing: 6) {
            // Colour comes from the screen: white over the camera, dark on Try On's light camera-off page.
            title.font(.system(size: 15, weight: .regular))
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { content() }
                        .scrollTargetLayout()
                        .frame(minHeight: rowHeight)
                }
                // Unclipped: the glass "none" circle's shadow reaches past the row and showed as a grey square when cut.
                .scrollClipDisabled()
                .contentMargins(.horizontal, max(geo.size.width / 2 - selectedWidth / 2, 0), for: .scrollContent)
                .scrollPosition(id: $position, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
                .onAppear { position = selectedID }
                .onChange(of: position) { _, id in
                    if let id, id != selectedID { onCenter(id) }
                }
                .onChange(of: selectedID) { _, id in
                    if position != id { withAnimation(.easeOut(duration: 0.25)) { position = id } }
                }
                .sensoryFeedback(.selection, trigger: position)
            }
            .frame(height: rowHeight)
        }
    }
}
