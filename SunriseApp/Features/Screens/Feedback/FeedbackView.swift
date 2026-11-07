import SwiftUI

/// The photo taken at the end of the tutorial: the plain camera (no virtual makeup) and, when blush was on, the blush
/// target outlines measured on that same frame. Memory only, like every photo in the app.
struct TutorialPhoto {
    let image: UIImage
    /// In the photo's own 0...1 coordinates (x right, y down). Nil when blush was off or no face was seen.
    let blushOutline: BlushGuideSnapshot?
}

/// What the feedback screen gets: what was chosen on Try On (with its look photo) and the photo taken after the tutorial.
struct FeedbackInput: Hashable {
    let handoff: TutorialHandoff
    let photo: TutorialPhoto
    var result: UIImage { photo.image }

    static func == (a: Self, b: Self) -> Bool {
        a.handoff == b.handoff && a.photo.image === b.photo.image && a.photo.blushOutline == b.photo.blushOutline
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(handoff)
        hasher.combine(ObjectIdentifier(photo.image))
    }
}

extension BlushGuideSnapshot {
    /// The outlines in 0...1 of a view of `size` (the engine gives them in that view's points). Nil for an empty size.
    func normalized(in size: CGSize) -> BlushGuideSnapshot? {
        guard size.width > 0, size.height > 0 else { return nil }
        func n(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / size.width, y: p.y / size.height) }
        return BlushGuideSnapshot(cheeks: cheeks.map {
            Cheek(inner: $0.inner.map(n), outer: $0.outer.map(n), center: n($0.center), outward: n($0.outward))
        })
    }

    /// Closed paths of the small circle and the outer line of every cheek, for a picture drawn in `rect`.
    func paths(in rect: CGRect) -> [Path] {
        func place(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        return cheeks.flatMap { [$0.inner, $0.outer] }.filter { $0.count > 2 }.map { points in
            Path { path in
                path.addLines(points.map(place))
                path.closeSubpath()
            }
        }
    }
}

/// After the tutorial's photo: the look chosen on Try On or the result, one large photo at a time, with the blush target
/// area drawn on the result. v1: no measuring yet (see `makeup-feedback.database.json` for what comes next).
struct FeedbackView: View {
    enum Shown: Hashable { case look, result }

    let input: FeedbackInput
    let onDone: () -> Void
    @State private var shown = Shown.result
    @State private var showsLines = true

    private var blushOn: Bool { input.handoff.enabled.contains(.blush) }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            Text("Your result").font(AppTypography.heading).accessibilityAddTraits(.isHeader)
            switcher
            photo
            caption
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Capsule().fill(AppColors.prepPink))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppColors.snow)
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var switcher: some View {
        HStack(spacing: 4) {
            choice(.look, title: String(localized: "Look"))
            choice(.result, title: String(localized: "Result"))
        }
        .padding(4)
        .glassCapsule(tint: AppColors.glassBase, interactive: false)
    }

    private func choice(_ value: Shown, title: String) -> some View {
        Button { shown = value } label: {
            Text(title)
                .font(.system(size: 15, weight: shown == value ? .semibold : .regular))
                .frame(minWidth: 96, minHeight: 36)
                .background { if shown == value { Capsule().fill(AppColors.glassSelected) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(shown == value ? .isSelected : [])
    }

    @ViewBuilder private var photo: some View {
        switch shown {
        case .look:
            if let look = input.handoff.lookPhoto {
                FeedbackPhoto(image: look, outline: nil, showsLines: false)
            } else {
                Text("No look photo yet")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.snow.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .result:
            FeedbackPhoto(image: input.result, outline: blushOn ? input.photo.blushOutline : nil, showsLines: showsLines)
                .onTapGesture { showsLines.toggle() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Shows or hides the blush target area"))
        }
    }

    @ViewBuilder private var caption: some View {
        if shown == .result && blushOn {
            Text(input.photo.blushOutline == nil
                 ? String(localized: "No lines: your face was not seen when the photo was taken.")
                 : String(localized: "Dotted lines = blush target area. Tap the photo to hide them."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.snow.opacity(0.85))
        }
    }
}

/// One photo, fitted whole, with the blush outlines drawn on the picture itself (not on the frame around it).
struct FeedbackPhoto: View {
    let image: UIImage
    let outline: BlushGuideSnapshot?
    let showsLines: Bool

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                if showsLines, let outline {
                    Canvas { context, size in
                        for path in outline.paths(in: CGRect(origin: .zero, size: size)) {
                            // The tutorial's own dotted line, so she recognises the area she followed.
                            context.stroke(path, with: .color(AppColors.snow.opacity(0.95)),
                                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 7]))
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showsLines)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
