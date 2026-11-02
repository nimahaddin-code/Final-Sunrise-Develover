import SwiftUI

/// The caption pill from the UX spec: SF Pro 15 pt, centred, 1 or 2 lines, on a `#370B21` rounded rectangle.
/// Used for camera messages and tutorial steps alike.
struct CameraCaption: View {
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 15

    static let fill = Color(red: 0x37 / 255, green: 0x0B / 255, blue: 0x21 / 255)

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .tracking(-0.43)
            // 22 pt line height on 15 pt type.
            .lineSpacing(4)
            .foregroundStyle(AppColors.snow)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
            .background(Self.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 300)
    }
}

/// "STEP 2 OF 3", above the caption (tutorial only).
struct CameraStepLabel: View {
    let text: LocalizedStringKey
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .tracking(2)
            .foregroundStyle(AppColors.snow.opacity(0.7))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .multilineTextAlignment(.center)
    }
}

/// What sits over the camera: the camera message when there is one, otherwise the tutorial step (label and caption).
/// With neither, nothing shows. Fades instead of sliding under Reduce Motion.
struct CameraGuidanceCaption: View {
    @ObservedObject var advisor: CameraAdvisor
    var lightOn: Bool
    var stepLabel: LocalizedStringKey?
    var stepText: LocalizedStringKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    var body: some View {
        VStack(spacing: 4) {
            if let message = advisor.message {
                CameraCaption(text: message.text(lightOn: lightOn))
                    .id(message)
                    .transition(transition)
            } else if let stepText {
                if let stepLabel { CameraStepLabel(text: stepLabel).transition(transition) }
                CameraCaption(text: stepText).id("step").transition(transition)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: advisor.message)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
