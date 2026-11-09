import SwiftUI

/// "Your feedback", after the result photo: a loading state while `provider` compares the two photos, then "Nice work!"
/// with the try-on and the result side by side under a drag divider, the overall match, placement and shade, retry (back to
/// the tutorial) and "Save look" (the share sheet, which can save the picture). Back returns home. The comparison is a
/// placeholder until the real one is plugged in through `MakeupFeedbackProviding`; parts it does not measure read "—".
struct FeedbackView: View {
    let handoff: TutorialHandoff
    @ObservedObject var store: MakeupFlowStore
    let provider: any MakeupFeedbackProviding
    let onBackToTutorial: () -> Void
    let onDone: () -> Void
    @State private var progress = 0.0
    @State private var feedback: MakeupFeedback?

    private static let ink = AppColors.onboardingInk
    private static let muted = AppColors.onboardingBody

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let feedback { result(feedback) } else { loading }
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.bottom, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { OnboardingGlow() }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .animation(.easeInOut(duration: 0.3), value: feedback)
        .sensoryFeedback(.success, trigger: feedback != nil)
        .task {
            guard feedback == nil else { return }
            let request = MakeupFeedbackRequest(tool: handoff.tool, styleTitle: handoff.styleTitle,
                                                desired: store.desired, result: store.result)
            feedback = await provider.feedback(for: request) { value in progress = value }
        }
    }

    /// Back (home), the style's name, share.
    private var header: some View {
        ZStack {
            Text(verbatim: handoff.styleTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.ink)
            HStack {
                Button(action: onDone) { circle("chevron.left") }
                    .accessibilityLabel("Done")
                Spacer()
                if let photo = store.result {
                    ShareLink(item: Image(uiImage: photo), preview: SharePreview(Text("My look"), image: Image(uiImage: photo))) {
                        circle("square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.small)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Self.ink)
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text("Checking your look")
                .font(.system(size: 30, weight: .black)).fontWidth(.expanded)
                .tracking(-0.6)
                .foregroundStyle(Self.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, AppSpacing.medium)
            ZStack {
                photo(store.result)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(Self.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.white.opacity(0.85), in: Capsule())
                    .contentTransition(.numericText())
                    .animation(.default, value: progress)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            ProgressView(value: progress).tint(AppColors.dandanPink)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your look")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func result(_ feedback: MakeupFeedback) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nice work!")
                        .font(.system(size: 30, weight: .black)).fontWidth(.expanded)
                        .tracking(-0.6)
                        .foregroundStyle(Self.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, AppSpacing.medium)
                    Text("Here's how close you got to your try-on.")
                        .font(.system(size: 14))
                        .foregroundStyle(Self.muted)
                        .padding(.top, 4)
                    CompareSlider(left: store.desired, right: store.result)
                        .frame(height: 210)
                        .padding(.top, AppSpacing.medium)
                    scoreCard(feedback).padding(.top, 12)
                    Text("What we think")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Self.ink)
                        .padding(.top, 22)
                    HStack(spacing: 12) {
                        partCard("Placement", symbol: "viewfinder", part: feedback.placement)
                        partCard("Shade", symbol: "paintpalette.fill", part: feedback.shade)
                    }
                    .padding(.top, 10)
                }
                .padding(.bottom, AppSpacing.medium)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 12) {
                Button(action: onBackToTutorial) { circle("arrow.clockwise") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to tutorial")
                saveButton
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private var saveButton: some View {
        let label = Label("Save look", systemImage: "heart")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(AppColors.buttonInk, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        if let photo = store.result {
            ShareLink(item: Image(uiImage: photo), preview: SharePreview(Text("My look"), image: Image(uiImage: photo))) { label }
                .buttonStyle(.plain)
        } else {
            label.opacity(0.45).accessibilityHint("No photo to save")
        }
    }

    /// The overall match as a ring, the headline and the first comment.
    private func scoreCard(_ feedback: MakeupFeedback) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(AppColors.dandanPink.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: feedback.score ?? 0)
                    .stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(percent(feedback.score))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(Self.ink)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.ink)
                if let comment = feedback.comments.first {
                    Text(comment).font(.system(size: 12)).foregroundStyle(Self.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func partCard(_ title: LocalizedStringKey, symbol: String, part: MakeupFeedback.Part?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
                    .frame(width: 24, height: 24)
                    .background(AppColors.dandanPink.opacity(0.1), in: Circle())
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Self.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percent(part?.value))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Self.ink)
                Text(verbatim: part?.note ?? String(localized: "Coming soon"))
                    .font(.system(size: 11))
                    .foregroundStyle(Self.muted)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.06))
                    Capsule().fill(AppColors.dandanPink).frame(width: proxy.size.width * (part?.value ?? 0))
                }
            }
            .frame(height: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
    }

    @ViewBuilder private func photo(_ image: UIImage?) -> some View {
        if let image {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            Color(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xE9 / 255)
                .overlay { Label("No photo taken", systemImage: "camera").font(.footnote).foregroundStyle(Self.muted) }
        }
    }
}

/// The try-on photo and the result photo in one frame, split by a divider the user drags.
private struct CompareSlider: View {
    let left: UIImage?
    let right: UIImage?
    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let x = proxy.size.width * split
            ZStack(alignment: .leading) {
                picture(right)
                picture(left).mask(alignment: .leading) { Rectangle().frame(width: x) }
                Rectangle().fill(.white).frame(width: 2).offset(x: x - 1)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .frame(width: 28, height: 28)
                    .background(.white, in: Circle())
                    .offset(x: x - 14)
                tag("Try-on", dot: false).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                tag("Yours", dot: true).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(value.location.x / proxy.size.width, 0.05), 0.95)
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Try-on and your result, side by side")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(split + 0.1, 0.95)
            case .decrement: split = max(split - 0.1, 0.05)
            @unknown default: break
            }
        }
    }

    @ViewBuilder private func picture(_ image: UIImage?) -> some View {
        if let image {
            Color.clear.overlay { Image(uiImage: LookBriefView.crop(image, for: .blush)).resizable().scaledToFill() }.clipped()
        } else {
            Color(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xE9 / 255)
        }
    }

    private func tag(_ text: LocalizedStringKey, dot: Bool) -> some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(AppColors.dandanPink).frame(width: 5, height: 5) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(AppColors.buttonInk, in: Capsule())
    }
}
