import SwiftUI

/// The eye scan result: three measured traits, plus the eyelid, which the camera cannot see and the person picks.
struct EyeShapeResultView: View {
    let result: EyeShapeResult
    var continueTitle: LocalizedStringKey = "See my makeup"
    var onChooseLid: (EyeLid?) -> Void
    var onScanAgain: () -> Void
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryCard
                lidCard
                if result.confidence < 0.25 {
                    Text("Some measurements sat close to the line between two shapes. If this does not look right, scan again facing the camera in good light.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                }
                Text("An estimate from your front camera, not a professional assessment. Only your eye shape result is kept on this device; no photos are saved or uploaded.")
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

    private var lidCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Which eyelid looks like yours?").font(AppTypography.heading)
            Text(result.mayBeHooded
                 ? "The space between your brow and lid looks small, which can mean a hooded lid. The camera cannot tell for sure, so you choose."
                 : "The camera cannot see your eyelid crease, so you choose.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            ForEach(EyeLid.allCases) { lid in
                Button { onChooseLid(result.lid == lid ? nil : lid) } label: {
                    HStack {
                        Text(lid.title)
                        Spacer()
                        if result.lid == lid { Image(systemName: "checkmark").foregroundStyle(AppColors.rose) }
                    }
                    .frame(minHeight: 44)
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
