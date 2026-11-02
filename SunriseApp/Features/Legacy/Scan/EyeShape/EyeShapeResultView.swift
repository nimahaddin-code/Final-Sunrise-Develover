import SwiftUI

/// The eye scan result: three measured traits, plus the eyelid, which the camera cannot see and the person picks.
struct EyeShapeResultView: View {
    let result: EyeShapeResult
    /// The scan picture with the measured lines; shown when the camera could provide it.
    var snapshot: ScanSnapshot?
    var continueTitle: LocalizedStringKey = "See my makeup"
    var onChooseLid: (EyeLid?) -> Void
    var onScanAgain: () -> Void
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryCard
                if let snapshot { measurementCard(snapshot) }
                lidCard
                if result.confidence < 0.25 {
                    Text("Some measurements sat close to the line between two shapes. If this does not look right, scan again facing the camera in good light.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                }
                Text("An estimate from your front camera, not a professional assessment. Only your eye shape result and one small photo from the scan are kept on this device; nothing is uploaded.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                PrimaryButton(title: continueTitle, action: onContinue)
                Button("Scan again", action: onScanAgain)
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(AppSpacing.large)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Image(systemName: "eye").font(.largeTitle).foregroundStyle(AppColors.rose).accessibilityHidden(true)
            Text("Your eye shape").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            trait("Shape", Text(result.openness.title))
            trait("Tilt", Text(result.tilt.title))
            trait("Spacing", Text(result.spacing.title))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private func trait(_ name: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(name).font(AppTypography.body).foregroundStyle(AppColors.subtle)
            Spacer()
            value.font(AppTypography.heading)
        }
    }

    private func measurementCard(_ snapshot: ScanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("What we measured").font(AppTypography.heading)
            ScanOverlayView(snapshot: snapshot)
            Text("The solid lines trace your eyes. The dashed lines are the tilt, the opening and the space between your eyes. If they do not sit on your eyes, scan again. This picture is not saved.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    private var lidCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Which eyelid looks like yours?").font(AppTypography.heading)
            Text(result.mayBeHooded
                 ? "The space between your brow and lid looks small, which can mean a hooded lid. The camera cannot tell for sure, so you choose."
                 : "The camera cannot see your eyelid crease, so you choose.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            Text("Tip: look straight into a mirror with your eyes open and relaxed, then compare.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            ForEach(EyeLid.allCases) { lid in
                Button { onChooseLid(result.lid == lid ? nil : lid) } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lid.title)
                            Text(lid.detail).font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        if result.lid == lid { Image(systemName: "checkmark").foregroundStyle(AppColors.rose) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(result.lid == lid ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }
}

#Preview {
    let measurements = EyeMeasurements(openness: 0.32, tilt: 5, spacing: 1.0, lidSpace: 0.7)
    return EyeShapeResultView(result: EyeShapeClassifier().classify(measurements), onChooseLid: { _ in },
                              onScanAgain: {}, onContinue: {})
}
