import SwiftUI

/// After the result photo: a loading state while `provider` compares the photos, then the feedback (design "18 · Your
/// feedback"): the look's name, a headline from the score, Before / After with a slider, the score ring with what to fix
/// first, and one card per measured category; a card opens every message of that category. -Nimah: redesign 2026-11-09.
struct FeedbackView: View {
    let handoff: TutorialHandoff
    @ObservedObject var store: MakeupFlowStore
    let provider: any MakeupFeedbackProviding
    let onBackToTutorial: () -> Void
    let onDone: () -> Void
    @State private var progress = 0.0
    @State private var feedback: MakeupFeedback?
    @State private var opened: MakeupFeedback.Category?
    @AppStorage(DeveloperTools.key) private var developerTools = false

    var body: some View {
        Group {
            if let feedback { result(feedback) } else { loading }
        }
        .foregroundStyle(AppColors.onboardingInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { OnboardingGlow().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .animation(.easeInOut(duration: 0.3), value: feedback)
        .sensoryFeedback(.success, trigger: feedback != nil)
        .sheet(item: $opened) { category in FeedbackCategorySheet(category: category) }
        .task {
            guard feedback == nil else { return }
            let request = MakeupFeedbackRequest(tool: handoff.tool, styleTitle: handoff.styleTitle,
                                                desired: store.desired, result: store.result,
                                                blushStyle: handoff.blushStyle, linerLook: handoff.linerLook,
                                                shade: handoff.shades[handoff.tool],
                                                desiredScan: store.desiredScan, resultScan: store.resultScan)
            feedback = await provider.feedback(for: request) { value in progress = value }
        }
    }

    // MARK: Loading

    private var loading: some View {
        VStack(spacing: AppSpacing.medium) {
            Text("Checking your look")
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, AppSpacing.large)
            ZStack {
                if let photo = store.result {
                    Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }.clipped()
                } else {
                    FlowPlaceholderBox(label: "No photo taken", symbol: "camera")
                }
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(AppColors.onboardingInk)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(.white.opacity(0.9), in: Capsule())
                    .contentTransition(.numericText())
                    .animation(.default, value: progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxHeight: .infinity)
            Text(lookTitle).font(.title3.weight(.semibold))
            ProgressView(value: progress).tint(AppColors.dandanPink)
                .padding(.bottom, AppSpacing.medium)
        }
        .padding(.horizontal, AppSpacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your look")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    // MARK: Result

    private func result(_ feedback: MakeupFeedback) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    topBar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(feedback.score))
                            .font(.system(size: 40, weight: .black))
                            .accessibilityAddTraits(.isHeader)
                        Text(feedback.score == nil ? "Let's take the photo again so we can check it."
                                                   : "Here's how close you got to your try-on.")
                            .font(.callout)
                            .foregroundStyle(AppColors.onboardingBody)
                    }
                    BeforeAfterSlider(before: store.bare ?? store.desired, after: store.result)
                        .frame(height: 360)
                    if let score = feedback.score {
                        scoreCard(score: score, feedback: feedback)
                    } else {
                        ForEach(feedback.items, id: \.self) { FeedbackMessageRow(item: $0).feedbackCard() }
                    }
                    if !feedback.categories.isEmpty {
                        Text("What we think")
                            .font(.title2.weight(.bold))
                            .padding(.top, AppSpacing.small)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(feedback.categories) { category in
                                Button { opened = category } label: { FeedbackCategoryCard(category: category) }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(Text("Shows how to fix it"))
                            }
                        }
                    }
                    if feedback.score != nil, !feedback.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Photo tips").font(.headline)
                            ForEach(feedback.notes, id: \.self) { note in
                                Text(note.say).font(.footnote).foregroundStyle(AppColors.onboardingBody)
                            }
                        }
                        .feedbackCard()
                    }
                    if developerTools { diagnostics }
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.bottom, AppSpacing.large)
            }
            bottomBar
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        ZStack {
            Text(lookTitle).font(.headline).lineLimit(1).padding(.horizontal, 64)
            HStack {
                circleButton(symbol: "chevron.left", label: "Done", action: onDone)
                Spacer()
                if let after = store.result {
                    ShareLink(item: Image(uiImage: after), preview: SharePreview(lookTitle, image: Image(uiImage: after))) {
                        circleLabel(symbol: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share photo")
                }
            }
        }
        .padding(.top, AppSpacing.small)
    }

    private func scoreCard(score: Double, feedback: MakeupFeedback) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(AppColors.dandanPink.opacity(0.18), lineWidth: 9)
                Circle().trim(from: 0, to: score)
                    .stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.headline).font(.headline)
                if !feedback.summary.isEmpty {
                    Text(feedback.summary).font(.subheadline).foregroundStyle(AppColors.onboardingBody)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .feedbackCard()
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        HStack(spacing: AppSpacing.medium) {
            circleButton(symbol: "arrow.clockwise", label: "Back to tutorial", action: onBackToTutorial)
            if let after = store.result {
                // "Save look": the share sheet, where "Save Image" puts it in the person's own photos. The app keeps nothing.
                ShareLink(item: Image(uiImage: after), preview: SharePreview(lookTitle, image: Image(uiImage: after))) {
                    saveLabel
                }
            } else {
                Button(action: onDone) { saveLabel }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.vertical, AppSpacing.small)
    }

    private var saveLabel: some View {
        Label(store.result == nil ? "Done" : "Save look", systemImage: store.result == nil ? "checkmark" : "heart")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(AppColors.buttonInk, in: Capsule())
    }

    private func circleButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func circleLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AppColors.onboardingInk)
            .frame(width: 56, height: 56)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Developer: shutters").font(.caption.weight(.semibold))
            ForEach([(CaptureStage.desired, "desired"), (.result, "result")], id: \.1) { stage, name in
                Text(verbatim: "\(name): \(store.diagnostics[stage]?.line ?? "no shutter")")
                    .font(.caption2.monospaced())
            }
            if let feedback {
                Text(verbatim: "rules: " + feedback.categories.flatMap(\.items).map(\.rule).joined(separator: ", "))
                    .font(.caption2.monospaced())
            }
        }
        .foregroundStyle(AppColors.onboardingBody)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Blush · Sunkissed".
    private var lookTitle: String {
        let tool: String = switch handoff.tool {
        case .blush: String(localized: "Blush")
        case .eyeliner: String(localized: "Eyeliner")
        case .eyebrow: String(localized: "Eyebrow")
        }
        let look: String? = switch handoff.tool {
        case .blush: handoff.blushStyle?.title
        case .eyebrow: handoff.browOverlay?.title
        case .eyeliner: String(localized: handoff.linerLook.title)
        }
        return look.map { "\(tool) · \($0)" } ?? tool
    }

    private func headline(_ score: Double?) -> String {
        guard let score else { return String(localized: "Retake the photo") }
        switch score {
        case 0.9...: return String(localized: "Perfect!")
        case 0.75...: return String(localized: "Nice work!")
        case 0.55...: return String(localized: "Almost there!")
        default: return String(localized: "Let's try again!")
        }
    }
}

/// Before (bare face) and After (the result) in one frame, split by a line the person drags.
private struct BeforeAfterSlider: View {
    let before: UIImage?
    let after: UIImage?
    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                photo(before)
                photo(after)
                    .mask(alignment: .trailing) { Rectangle().frame(width: width * (1 - split)) }
                Rectangle().fill(.white).frame(width: 3).offset(x: width * split - 1.5)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .offset(x: width * split - 26)
                VStack {
                    Spacer()
                    HStack {
                        tag("Before", dot: false)
                        Spacer()
                        tag("After", dot: true)
                    }
                    .padding(14)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(value.location.x / max(width, 1), 0.05), 0.95)
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Before and after photos")
        .accessibilityAdjustableAction { direction in
            split = min(max(split + (direction == .increment ? 0.1 : -0.1), 0.05), 0.95)
        }
    }

    @ViewBuilder private func photo(_ image: UIImage?) -> some View {
        if let image {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            FlowPlaceholderBox(label: "No photo", symbol: "camera")
        }
    }

    private func tag(_ title: LocalizedStringKey, dot: Bool) -> some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(AppColors.dandanPink).frame(width: 8, height: 8) }
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.85), in: Capsule())
    }
}

/// One category: its symbol and name, percentage with a short label, and a bar.
private struct FeedbackCategoryCard: View {
    let category: MakeupFeedback.Category

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
                    .frame(width: 36, height: 36)
                    .background(AppColors.dandanPink.opacity(0.12), in: Circle())
                Text(category.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppColors.onboardingBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(category.percent, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                Text(category.label)
                    .font(.footnote)
                    .foregroundStyle(AppColors.onboardingBody)
                    .lineLimit(2)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.onboardingBody.opacity(0.15))
                    Capsule().fill(AppColors.dandanPink).frame(width: proxy.size.width * category.percent)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .feedbackCard()
        .accessibilityElement(children: .combine)
    }
}

/// Every message of one category, opened from its card.
private struct FeedbackCategorySheet: View {
    let category: MakeupFeedback.Category
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if category.items.isEmpty {
                        FeedbackMessageRow(item: .init(title: String(localized: "Spot on"),
                                                       say: String(localized: "Nothing to fix here. Keep doing it this way."),
                                                       steps: [], band: .ok))
                            .feedbackCard()
                    }
                    ForEach(category.items, id: \.self) { FeedbackMessageRow(item: $0).feedbackCard() }
                }
                .padding(AppSpacing.medium)
            }
            .background(AppColors.homeCanvas)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One message: what is off, how to fix it, and the steps when it is easier to redo.
private struct FeedbackMessageRow: View {
    let item: MakeupFeedback.Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(item.band == .ok ? Color.green : AppColors.dandanPink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline)
                Text(item.say).font(.subheadline).foregroundStyle(AppColors.onboardingBody)
                ForEach(Array(item.steps.enumerated()), id: \.offset) { index, step in
                    Text(verbatim: "\(index + 1). \(step)").font(.footnote).foregroundStyle(AppColors.onboardingBody)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(AppColors.onboardingInk)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch item.band {
        case .ok: "checkmark.circle.fill"
        case .slight: "lightbulb.fill"
        case .clear, .large: "exclamationmark.circle.fill"
        }
    }
}

private extension View {
    /// The design's white card: rounded, soft shadow.
    func feedbackCard() -> some View {
        padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}
