import SwiftUI

/// The saved analysis: face shape, eye shape and the signature look assigned to them. Opened from the Try On home
/// profile button, so people can revisit what the first scan found. Portraits come from `ScanSnapshots`, the still
/// kept from each scan; without one the circle shows an icon.
struct ProfileView: View {
    @ObservedObject var store: FaceShapeStore
    var onTry: () -> Void
    @State private var faceImage: UIImage?
    @State private var eyeImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                section("Face Shape Analysis") { faceSection }
                section("Eye Shape Analysis") { eyeSection }
                Text("An estimate from your camera, not a professional assessment. Your results and one small photo from each scan stay on this device; nothing is uploaded.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.snow.opacity(0.7))
                    .multilineTextAlignment(.center)
                actions
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.medium)
        }
        .background(AppColors.screen.ignoresSafeArea())
        .foregroundStyle(AppColors.snow)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(AppColors.snow)
        .onAppear {
            faceImage = ScanSnapshots.load(.face)
            eyeImage = ScanSnapshots.load(.eyes)
        }
    }

    // MARK: Face

    @ViewBuilder private var faceSection: some View {
        if let result = store.latest {
            let mapped = Self.makeupShape(result.shape)
            portrait { FaceOutline(shape: result.shape).stroke(AppColors.snow, style: StrokeStyle(lineWidth: 3, dash: [7, 6])).padding(34) }
            Text(result.shape.title).font(.system(.largeTitle, design: .rounded).weight(.bold))
            closestMatches(result)
            card("Your Features") {
                tile("Forehead", symbol: "arrow.up.and.down.and.arrow.left.and.right")
                tile("Chin", symbol: "chevron.down")
                tile("Cheek", symbol: "circle.dotted")
            }
            card("Your Signature Look") {
                tile("Brows", symbol: "eyebrow", detail: MakeupPreferenceCatalog.assignedBrow(for: mapped).map { Text($0.style.title) })
                tile("Blush", symbol: "paintbrush.pointed", detail: MakeupPreferenceCatalog.assignedBlush(for: mapped).map { Text($0.style.title) })
                tile("Eyeliner", symbol: "pencil.tip", detail: linerName.map { Text($0) })
            }
        } else {
            empty("No saved face scan yet.")
        }
    }

    // MARK: Eyes

    @ViewBuilder private var eyeSection: some View {
        if let eyes = store.eyes {
            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous).fill(AppColors.cocoa)
                if let eyeImage {
                    Image(uiImage: eyeImage).resizable().scaledToFill()
                } else {
                    Image(systemName: "eye").font(.system(size: 52)).foregroundStyle(AppColors.snow.opacity(0.9))
                }
            }
            .aspectRatio(2.1, contentMode: .fit)
            .frame(maxWidth: 280)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .accessibilityHidden(true)
            Text(eyes.openness.title).font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("\(Text(eyes.tilt.title)) · \(Text(eyes.spacing.title))")
                .font(AppTypography.caption).foregroundStyle(AppColors.snow.opacity(0.75))
            eyelidPicker(eyes)
            card("Your Signature Look") {
                tile("Eyeliner", symbol: "pencil.tip", detail: linerName.map { Text($0) })
                tile("Lashes", symbol: "eyelashes")
            }
        } else {
            empty("No saved eye scan yet.")
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: AppSpacing.medium) {
            Button(action: onTry) {
                Text("Try My Signature Look").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppColors.flamingo, in: Capsule())
                    .foregroundStyle(AppColors.snow)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Pieces

    private var linerName: LocalizedStringResource? {
        let plan = store.latest.map { MakeupPlan(scan: $0, eyeScan: store.eyes) } ?? MakeupPlan(shape: .oval, eyeScan: store.eyes)
        return plan.eyeliner.isNeutral ? nil : plan.eyeliner.primary?.title
    }

    /// The three nearest face shapes with their scores, as on the scan result.
    private func closestMatches(_ result: FaceShapeResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Closest matches").font(.headline)
            ForEach(result.rankedShapes.prefix(3), id: \.shape) { match in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label { Text(match.shape.title) } icon: { Image(systemName: match.shape.symbol) }
                        Spacer()
                        Text(match.score, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }
                    .font(.subheadline)
                    ProgressView(value: match.score).tint(AppColors.flamingo)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.snow.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
    }

    /// The eyelid the person chose after the eye scan; changing it here updates the saved result.
    private func eyelidPicker(_ eyes: EyeShapeResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Your Eyelid").font(.headline)
            Picker("Eyelid", selection: Binding(get: { store.eyes?.lid ?? eyes.lid }, set: { store.eyes?.lid = $0 })) {
                Text("Not chosen").tag(EyeLid?.none)
                ForEach(EyeLid.allCases) { Text($0.title).tag(EyeLid?.some($0)) }
            }
            .pickerStyle(.segmented)
            Text("The camera cannot see the crease, so this one is up to you.")
                .font(AppTypography.caption).foregroundStyle(AppColors.snow.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.snow.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Text(title).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func portrait<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle().fill(AppColors.cocoa)
            if let faceImage {
                Image(uiImage: faceImage).resizable().scaledToFill().clipShape(Circle())
            } else {
                Image(systemName: "person.fill").font(.system(size: 76)).foregroundStyle(AppColors.snow.opacity(0.25))
            }
            content()
        }
        .frame(width: 156, height: 156)
        .accessibilityHidden(true)
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title).font(.headline)
            HStack(alignment: .top, spacing: AppSpacing.medium) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.medium)
        .background(AppColors.snow.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
    }

    /// A square swatch with its name below; the placeholder tone stays until real reference art exists.
    private func tile(_ name: LocalizedStringKey, symbol: String, detail: Text? = nil) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(white: 0.86))
                .aspectRatio(1, contentMode: .fit)
                .overlay { Image(systemName: symbol).font(.title).foregroundStyle(AppColors.wine.opacity(0.55)) }
            Text(name).font(.footnote.weight(.semibold))
            if let detail {
                detail.font(.caption2).foregroundStyle(AppColors.snow.opacity(0.75)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func empty(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Text(message).font(AppTypography.body).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.large)
        .background(AppColors.snow.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // Same adapter as `AppRootView.studioAssessment`.
    private static func makeupShape(_ shape: FaceShape) -> MakeupFaceShape {
        shape == .triangle ? .pear : MakeupFaceShape(rawValue: shape.rawValue) ?? .unknown
    }
}

/// A simple outline of each face shape, drawn in the rect it is given.
private struct FaceOutline: Shape {
    let shape: FaceShape

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        switch shape {
        case .oval: return Path(ellipseIn: rect.insetBy(dx: rect.width * 0.12, dy: 0))
        case .round:
            let side = min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        case .square: return Path(roundedRect: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06), cornerRadius: rect.width * 0.18)
        case .oblong: return Path(roundedRect: rect.insetBy(dx: rect.width * 0.18, dy: 0), cornerRadius: rect.width * 0.3)
        case .heart: return polygon([p(0.05, 0.12), p(0.95, 0.12), p(0.8, 0.6), p(0.5, 1), p(0.2, 0.6)])
        case .diamond: return polygon([p(0.5, 0), p(1, 0.42), p(0.5, 1), p(0, 0.42)])
        case .triangle: return polygon([p(0.28, 0.05), p(0.72, 0.05), p(1, 0.9), p(0, 0.9)])
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

#Preview {
    let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
    let face = classifier.classify(FaceProportions(length: 1.2, forehead: 0.89, jaw: 0.76, chin: 0.47))
    return NavigationStack {
        ProfileView(store: FaceShapeStore(latest: face,
                                          eyes: EyeShapeClassifier().classify(EyeMeasurements(openness: 0.32, tilt: 5, spacing: 1.0, lidSpace: 0.7))),
                    onTry: {})
    }
}
