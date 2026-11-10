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
    /// The result photo lined up with the Before photo, the try-on taken at the desired-look shutter (`PhotoAlignment`).
    @State private var alignedResult: UIImage?
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
            if let before = store.desired, let result = store.result {
                alignedResult = PhotoAlignment.align(after: result, afterScan: store.resultScan, to: before, beforeScan: store.desiredScan)
            }
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your look")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func result(_ feedback: MakeupFeedback) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(feedback.score))
                            .font(.system(size: 32, weight: .black)).fontWidth(.expanded)
                            .tracking(-0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                        Text(feedback.score == nil ? "Let's take the photo again so we can check it."
                                                   : "Here's how close you got to your try-on.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.onboardingBody)
                    }
                    BeforeAfterSlider(before: store.desired ?? store.bare, after: alignedResult ?? store.result)
                        .aspectRatio(362 / 236, contentMode: .fit)
                    if let score = feedback.score {
                        scoreCard(score: score, feedback: feedback)
                        FeedbackFixes(feedback: feedback, photo: store.result)
                    } else {
                        ForEach(feedback.items, id: \.self) { FeedbackMessageRow(item: $0).feedbackCard() }
                    }
                    if !feedback.categories.isEmpty {
                        Text("What we think")
                            .font(.system(size: 22, weight: .bold))
                            .padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(feedback.categories) { category in
                                Button { opened = category } label: { FeedbackCategoryCard(category: category) }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(Text("Shows how to fix it"))
                            }
                        }
                    }
                    if developerTools { diagnostics }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, AppSpacing.large)
            }
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        ZStack {
            Text(lookTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1).padding(.horizontal, 64)
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
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(AppColors.dandanPink.opacity(0.18), lineWidth: 6)
                Circle().trim(from: 0, to: score)
                    .stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(feedback.headline).font(.system(size: 17, weight: .semibold))
                if !feedback.summary.isEmpty {
                    Text(feedback.summary).font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .feedbackCard()
        .accessibilityElement(children: .combine)
    }

    /// Retry (back to the tutorial) and Done (home). Saving the photo is the share button at the top.
    private var bottomBar: some View {
        HStack(spacing: 12) {
            circleButton(symbol: "arrow.clockwise", label: "Back to tutorial", action: onBackToTutorial)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppColors.buttonInk, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, AppSpacing.small)
    }

    private func circleButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func circleLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppColors.onboardingInk)
            .frame(width: 48, height: 48)
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

/// Before (the try-on photo) and After (the result) in one frame, split by a line the person drags.
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .offset(x: width * split - 18)
                VStack {
                    Spacer()
                    HStack {
                        tag("Before", dot: false)
                        Spacer()
                        tag("After", dot: true)
                    }
                    .padding(10)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(value.location.x / max(width, 1), 0.05), 0.95)
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        HStack(spacing: 5) {
            if dot { Circle().fill(AppColors.dandanPink).frame(width: 6, height: 6) }
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.85), in: Capsule())
    }
}

/// -Nimah: the first fix in its own card with the marked photo crop, the next ones numbered under it, then what went
/// well. Plain words, no millimetres: the crop shows where.
struct FeedbackFixes: View {
    let feedback: MakeupFeedback
    /// The result photo the marks are placed on.
    let photo: UIImage?

    var body: some View {
        let fixes = feedback.fixes
        VStack(alignment: .leading, spacing: 14) {
            if let first = fixes.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fix this first")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.dandanPink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(AppColors.dandanPink.opacity(0.12), in: Capsule())
                    if let photo, let mark = feedback.mark(for: first), !mark.target.isEmpty {
                        FixCrop(photo: photo, mark: mark)
                    }
                    Text(first.title).font(.system(size: 17, weight: .semibold))
                    Text(first.say).font(.system(size: 14)).foregroundStyle(AppColors.onboardingBody)
                    ForEach(Array(first.steps.enumerated()), id: \.offset) { index, step in
                        Text(verbatim: "\(index + 1). \(step)").font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .feedbackCard()
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColors.dandanPink.opacity(0.5), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            if fixes.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Next").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.onboardingBody)
                    ForEach(Array(fixes.dropFirst().enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(verbatim: "\(index + 2)")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(AppColors.dandanPink, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 15, weight: .semibold))
                                Text(item.say).font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .feedbackCard()
            }
            if !feedback.praise.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What went well").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.onboardingBody)
                    ForEach(feedback.praise, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(item.title).foregroundStyle(AppColors.onboardingInk)
                        }
                        .font(.system(size: 14))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .feedbackCard()
            }
        }
    }
}

/// -Nimah: the result photo cropped to the fix's side, with the target as faint dots, the target spots still bare as
/// rings ("add here") and the makeup outside the target filled ("wipe off").
private struct FixCrop: View {
    let photo: UIImage
    let mark: MakeupFeedback.Mark
    static let aspect: CGFloat = 2.2

    var body: some View {
        let rect = Self.crop(mark, photo: photo.size)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let size = proxy.size
                let scale = size.width / max(rect.width * photo.size.width, 1)
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: photo.size.width * scale, height: photo.size.height * scale)
                    .offset(x: -rect.minX * photo.size.width * scale, y: -rect.minY * photo.size.height * scale)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .overlay {
                        Canvas { context, size in
                            func place(_ p: CGPoint) -> CGPoint {
                                CGPoint(x: (p.x - rect.minX) / rect.width * size.width, y: (p.y - rect.minY) / rect.height * size.height)
                            }
                            let r = max(1.4, size.width / 140)
                            func dot(_ p: CGPoint, _ radius: CGFloat) -> Path {
                                let c = place(p); return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                            }
                            let pink = AppColors.dandanPink
                            for p in mark.target { context.fill(dot(p, r * 0.6), with: .color(pink.opacity(0.25))) }
                            for p in mark.remove { context.fill(dot(p, r), with: .color(pink.opacity(0.6))) }
                            for p in mark.add { context.stroke(dot(p, r), with: .color(pink), lineWidth: 1.2) }
                        }
                    }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 14) {
                if !mark.add.isEmpty { legend(Circle().stroke(AppColors.dandanPink, lineWidth: 1.2), "Add here") }
                if !mark.remove.isEmpty { legend(Circle().fill(AppColors.dandanPink.opacity(0.6)), "Wipe off") }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo of the area to fix")
    }

    private func legend(_ shape: some View, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            shape.frame(width: 9, height: 9)
            Text(title).font(.system(size: 11)).foregroundStyle(AppColors.onboardingBody)
        }
    }

    /// The part of the photo (0...1) around the mark, padded, at `aspect` in pixels and kept inside the photo.
    static func crop(_ mark: MakeupFeedback.Mark, photo: CGSize) -> CGRect {
        let points = mark.target + mark.add + mark.remove
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), photo.width > 0, photo.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        var w = max((maxX - minX) * 1.5, 0.3), h = max((maxY - minY) * 1.5, 0.05)
        // Same shape as the frame: width / height in pixels = aspect.
        let wanted = w * photo.width / aspect / photo.height
        if h < wanted { h = wanted } else { w = h * photo.height * aspect / photo.width }
        if w > 1 { h *= 1 / w; w = 1 }
        if h > 1 { w *= 1 / h; h = 1 }
        let x = min(max((minX + maxX) / 2 - w / 2, 0), 1 - w), y = min(max((minY + maxY) / 2 - h / 2, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// One category: its symbol and name, percentage with a short label, and a bar.
private struct FeedbackCategoryCard: View {
    let category: MakeupFeedback.Category

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
                    .frame(width: 30, height: 30)
                    .background(AppColors.dandanPink.opacity(0.12), in: Circle())
                Text(category.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AppColors.onboardingBody)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(category.percent, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                Text(category.label)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.onboardingBody)
                    .lineLimit(2)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.onboardingBody.opacity(0.15))
                    Capsule().fill(AppColors.dandanPink).frame(width: proxy.size.width * category.percent)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .feedbackCard()
        .accessibilityElement(children: .combine)
    }
}

/// -Nimah: every message of one category, opened from its card.
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
        .preferredColorScheme(.light)
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
                Text(item.title).font(.system(size: 15, weight: .semibold))
                Text(item.say).font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
                ForEach(Array(item.steps.enumerated()), id: \.offset) { index, step in
                    Text(verbatim: "\(index + 1). \(step)").font(.system(size: 12)).foregroundStyle(AppColors.onboardingBody)
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
    /// The design's white card.
    func feedbackCard() -> some View {
        padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}
