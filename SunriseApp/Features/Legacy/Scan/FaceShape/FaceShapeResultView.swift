import SwiftUI

struct FaceShapeResultView: View {
    let result: FaceShapeResult
    @AppStorage(DeveloperTools.key) private var developerTools = false
    /// The scan picture with the measured lines; shown when the camera could provide it.
    var snapshot: ScanSnapshot?
    var continueTitle: LocalizedStringKey = "Try on recommended makeup"

    var onScanAgain: () -> Void
    /// Called when the person answers the hooded / monolid question.
    var onLidTypeChange: (LidType) -> Void = { _ in }
    var onShowMakeup: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryCard
                eyeCard
                // -Nimah: Blush guidance now belongs exclusively to Nimah studio.
                if let snapshot { measurementCard(snapshot) }
                card(title: "Closest matches") {
                    ForEach(result.rankedShapes.prefix(3), id: \.shape) { match in
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            HStack {
                                Label { Text(match.shape.title) } icon: { Image(systemName: match.shape.symbol) }
                                Spacer()
                                Text(match.score, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            ProgressView(value: match.score).tint(AppColors.rose)
                        }
                    }
                }
                Text("An estimate from ARKit's face mesh, not a professional assessment. Only the face shape, eye measurements and one small photo from the scan are kept on this device; nothing is uploaded.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                if DeveloperTools.isOn(developerTools) { EyeDebugView(eyes: result.eyes) }
                if let onShowMakeup {
                    PrimaryButton(title: continueTitle, action: onShowMakeup)
                    Button("Scan again", action: onScanAgain)
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    PrimaryButton(title: "Scan again", action: onScanAgain)
                }
            }
            .padding(AppSpacing.large)
        }
    }

    /// The eye shape from the scan, and the question the camera cannot answer: hooded or monolid lids.
    private var eyeCard: some View {
        card(title: "Your eye shape") {
            if let eyes = result.eyes {
                let plan = EyelinerPlanner.plan(for: eyes)
                if plan.isNeutral {
                    Text("Your eye shape was not clear enough to tell. Scan again with your eyes relaxed and open for a tailored eyeliner.")
                        .font(AppTypography.body)
                } else {
                    ForEach(plan.blend, id: \.shape) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Text(item.shape.title)) \(item.weight, format: .percent.precision(.fractionLength(0)))")
                                .font(AppTypography.body.weight(.semibold))
                            Text(item.shape.summary).font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Do your eyelids look hooded or monolid?").font(AppTypography.body)
                    Picker("Eyelids", selection: Binding(get: { eyes.lidType }, set: onLidTypeChange)) {
                        ForEach(LidType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("The camera cannot see the crease, so this one is up to you.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                }
            } else {
                Text("Your eyes were not measured in this scan. Scan again to get an eyeliner chosen for your eye shape.")
                    .font(AppTypography.body)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Image(systemName: result.shape.symbol).font(.largeTitle).foregroundStyle(AppColors.rose)
                .accessibilityHidden(true)
            Text("Your face shape").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            Text(result.shape.title).font(AppTypography.title)
            Text(result.shape.summary).font(AppTypography.body)
            Text("Also close to \(Text(result.runnerUp.title)).")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    private func measurementCard(_ snapshot: ScanSnapshot) -> some View {
        card(title: "What we measured") {
            ScanOverlayView(snapshot: snapshot)
            Text("The solid line follows your face. The dashed lines are the forehead, cheekbone and jaw widths and the face length. If they do not sit on your face, scan again. This picture is not saved.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
        }
    }

    private func card<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(title).font(AppTypography.heading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }
}

#Preview {
    let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
    return FaceShapeResultView(result: classifier.classify(FaceProportions(length: 1.2, forehead: 0.89, jaw: 0.76, chin: 0.47)),
                               onScanAgain: {})
}
