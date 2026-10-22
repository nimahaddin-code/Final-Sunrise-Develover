import SwiftUI

/// Eyebrow, blush and eyeliner styles recommended for the scanned face shape; each one opens the live try-on.
struct MakeupRecommendationsView: View {
    @ObservedObject var store: FaceShapeStore
    var onScanFace: () -> Void
    var onScanEyes: () -> Void = {}
    /// A shape the user picked instead of the scanned one; cleared by a new scan.
    @State private var chosenShape: FaceShape?

    var body: some View {
        Group {
            if let result = store.latest {
                recommendations(for: chosenShape ?? result.shape, scan: result)
            } else {
                ContentUnavailableView {
                    Label("Scan your face first", systemImage: "face.dashed")
                } description: {
                    Text("Eyebrow, blush and eyeliner recommendations are based on your face shape.")
                } actions: {
                    Button("Scan face shape", action: onScanFace)
                        .buttonStyle(.borderedProminent).tint(AppColors.rose)
                }
            }
        }
        .background(AppColors.background)
        .foregroundStyle(AppColors.ink)
        .navigationTitle("Try On")
        .toolbar {
            if store.latest != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onScanFace) { Label("Scan face again", systemImage: "face.dashed") }
                }
            }
        }
        .onChange(of: store.latest) { chosenShape = nil }
    }

    private func recommendations(for shape: FaceShape, scan: FaceShapeResult) -> some View {
        let plan = MakeupPlan(scan: scan, chosenShape: chosenShape)
        return List {
            Section {
                summary(for: shape, scan: scan)
                if chosenShape == nil, plan.blend.count > 1 {
                    blendSummary(plan.blend)
                }
                NavigationLink(value: AppRoute.makeupTryOn(plan: plan, applied: plan.madeForYou)) {
                    Label("Try your made-for-you look live", systemImage: "camera.viewfinder")
                        .font(.headline).foregroundStyle(AppColors.rose)
                }
            }
            .listRowBackground(AppColors.card)
            Section { eyeCard }
                .listRowBackground(AppColors.card)
            ForEach(MakeupCategory.allCases) { category in
                Section {
                    let items = plan.recommendations(in: category)
                    let catalogBest = items.first { !MakeupPlan.isMadeForYou($0) }
                    ForEach(items) { recommendation in
                        NavigationLink(value: AppRoute.makeupTryOn(plan: plan, applied: [recommendation])) {
                            MakeupRecommendationRow(recommendation: recommendation,
                                                    badge: badge(for: recommendation, catalogBest: catalogBest))
                        }
                    }
                } header: {
                    Label { Text(category.title) } icon: { Image(systemName: category.symbol) }
                } footer: {
                    Text(plan.reason(for: category))
                }
                .listRowBackground(AppColors.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// The eye scan result, or an invitation to scan. The eye shape is shown but does not change the styles yet.
    @ViewBuilder private var eyeCard: some View {
        if let eyes = store.eyes {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                HStack(spacing: AppSpacing.medium) {
                    Image(systemName: "eye").font(.title).foregroundStyle(AppColors.rose).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.small / 2) {
                        Text("Your eye shape").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                        Text("\(Text(eyes.openness.title)) · \(Text(eyes.tilt.title)) · \(Text(eyes.spacing.title))")
                            .font(AppTypography.heading)
                        if let lid = eyes.lid {
                            Text(lid.title).font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                Button("Scan eyes again", action: onScanEyes)
                    .font(AppTypography.caption).foregroundStyle(AppColors.rose).buttonStyle(.plain)
            }
            .padding(.vertical, AppSpacing.small)
        } else {
            Button(action: onScanEyes) {
                Label("Scan your eye shape", systemImage: "eye").font(.headline).foregroundStyle(AppColors.rose)
            }
        }
    }

    private func badge(for recommendation: MakeupRecommendation,
                       catalogBest: MakeupRecommendation?) -> MakeupRecommendationRow.Badge? {
        if MakeupPlan.isMadeForYou(recommendation) { return .madeForYou }
        return recommendation == catalogBest ? .bestMatch : nil
    }

    /// Which shapes the made-for-you styles mix, so the result reads as personal rather than a label.
    private func blendSummary(_ blend: [ShapeWeight]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Your made-for-you styles mix").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            HStack(spacing: AppSpacing.small) {
                ForEach(blend, id: \.shape) { weight in
                    HStack(spacing: 4) {
                        Image(systemName: weight.shape.symbol).font(.caption2).accessibilityHidden(true)
                        Text("\(Text(weight.shape.title)) \(weight.weight, format: .percent.precision(.fractionLength(0)))")
                    }
                    .font(AppTypography.caption.weight(.medium))
                    .padding(.horizontal, AppSpacing.small).padding(.vertical, 4)
                    .background(AppColors.rose.opacity(0.08 + 0.2 * weight.weight), in: Capsule())
                }
            }
            Text("Tuned to your face length, forehead and jaw from the scan, then fitted to your eyes, brows and nose on camera.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.small / 2)
        .accessibilityElement(children: .combine)
    }

    private func summary(for shape: FaceShape, scan: FaceShapeResult) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: shape.symbol).font(.largeTitle).foregroundStyle(AppColors.rose)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.small / 2) {
                    Text(shape == scan.shape ? "Recommended for your face shape" : "Recommended for")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                    Text(shape.title).font(AppTypography.heading)
                }
                Spacer(minLength: 0)
                shapeMenu(current: shape, scanned: scan.shape)
            }
            .accessibilityElement(children: .contain)
            // The scan is an estimate, so offer the runner-up in one tap.
            if shape == scan.shape {
                Button {
                    chosenShape = scan.runnerUp
                } label: {
                    Text("Also close to \(Text(scan.runnerUp.title)). Show those instead")
                }
                .font(AppTypography.caption).foregroundStyle(AppColors.rose)
                .buttonStyle(.plain)
            } else {
                Button("Back to my scanned shape (\(Text(scan.shape.title)))") { chosenShape = nil }
                    .font(AppTypography.caption).foregroundStyle(AppColors.rose)
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppSpacing.small)
    }

    private func shapeMenu(current: FaceShape, scanned: FaceShape) -> some View {
        Menu {
            Picker("Face shape", selection: Binding(get: { current },
                                                    set: { chosenShape = $0 == scanned ? nil : $0 })) {
                ForEach(FaceShape.allCases) { shape in
                    Label {
                        Text(shape == scanned ? "\(Text(shape.title)) (scanned)" : "\(Text(shape.title))")
                    } icon: {
                        Image(systemName: shape.symbol)
                    }
                    .tag(shape)
                }
            }
        } label: {
            Text("Change").font(.subheadline.weight(.medium))
                .padding(.horizontal, AppSpacing.small + 4).padding(.vertical, 6)
                .background(AppColors.rose.opacity(0.12), in: Capsule())
                .foregroundStyle(AppColors.rose)
        }
        .accessibilityLabel("Change face shape")
    }

}

struct MakeupRecommendationRow: View {
    enum Badge { case madeForYou, bestMatch }

    let recommendation: MakeupRecommendation
    let badge: Badge?

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            MakeupSwatch(style: recommendation.style).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: AppSpacing.small / 2) {
                HStack(spacing: AppSpacing.small) {
                    Text(recommendation.name).font(.headline)
                    switch badge {
                    case .madeForYou:
                        Image(systemName: "sparkles").font(AppTypography.caption.weight(.semibold))
                            .padding(.horizontal, AppSpacing.small).padding(.vertical, 3)
                            .background(AppColors.rose, in: Capsule())
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                    case .bestMatch:
                        Text("Best match").font(AppTypography.caption.weight(.semibold))
                            .padding(.horizontal, AppSpacing.small).padding(.vertical, 2)
                            .background(AppColors.rose.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppColors.rose)
                    case nil:
                        EmptyView()
                    }
                }
                Text(recommendation.detail).font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            }
        }
        .padding(.vertical, AppSpacing.small / 2)
        .accessibilityElement(children: .combine)
    }
}

/// Colour dot for a makeup style.
struct MakeupSwatch: View {
    let style: MakeupStyle

    var body: some View {
        ShadeDot(shade: style.shade).accessibilityHidden(true)
    }
}

struct ShadeDot: View {
    let shade: MakeupShade

    var body: some View {
        Circle()
            .fill(Color(red: shade.red, green: shade.green, blue: shade.blue))
            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
    }
}

#Preview("Scanned") {
    let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
    let result = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
    return NavigationStack { MakeupRecommendationsView(store: FaceShapeStore(latest: result), onScanFace: {}) }
}

#Preview("Not scanned") {
    NavigationStack { MakeupRecommendationsView(store: FaceShapeStore(), onScanFace: {}) }
}
