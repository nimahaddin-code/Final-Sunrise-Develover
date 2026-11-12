import SwiftUI
import simd

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
                    // Before = the try-on photo (staging's fix). After = E2E-Flow's mesh-aligned result when it could be made,
                    // else staging's eye alignment, else the photo as taken.
                    BeforeAfterSlider(before: focused(store.desired ?? store.bare),
                                      after: focused(store.alignedResult ?? alignedResult ?? store.result))
                        .aspectRatio(362 / 236, contentMode: .fit)
                    // Design 18: "What we think", then the overall ring, then the Placement and Shade cards.
                    if feedback.score != nil || !feedback.categories.isEmpty {
                        Text("What we think")
                            .font(.system(size: 22, weight: .bold))
                            .padding(.top, 4)
                    }
                    if let score = feedback.score {
                        scoreCard(score: score, feedback: feedback)
                    } else {
                        ForEach(feedback.items, id: \.self) { FeedbackMessageRow(item: $0).feedbackCard() }
                    }
                    if !feedback.categories.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(feedback.categories) { category in
                                Button { opened = category } label: { FeedbackCategoryCard(category: category) }
                                    .buttonStyle(.plain)
                                    .accessibilityHint(Text("Shows how to fix it"))
                            }
                        }
                    }
                    if feedback.score != nil { FeedbackFixes(feedback: feedback, photo: store.result) }
                    if developerTools {
                        diagnostics
                        FeedbackPointCheck(store: store, feedback: feedback)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, AppSpacing.large)
            }
            .scrollIndicators(.hidden)
            // Retake (back to the tutorial) and Done (home), pinned under the scroll as in the design.
            bottomBar
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        ZStack {
            Text(lookTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1).padding(.horizontal, 64)
            HStack {
                circleButton(symbol: "chevron.left", label: "Done", action: onDone)
                Spacer()
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

    /// Brows and eyeliner compare the eye area only (the same crop as the brief, `LookBriefView.crop`), so the difference is
    /// big enough to see; blush keeps the whole face. Both photos are lined up first, so one crop fits both.
    private func focused(_ image: UIImage?) -> UIImage? {
        guard let image, handoff.tool != .blush else { return image }
        return LookBriefView.crop(image, for: handoff.tool)
    }

    /// Retry (back to the tutorial) and Done (home).
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
/// -Nimah: developer check that the feedback reads the right spots. Each photo with the points measured on it: a sparse
/// grid of face-mesh points (white), the eye centres (cyan) and, pink, what the feedback takes as the target: on Expected
/// the points the virtual makeup changed, on Result the target of every mark. Pink should sit exactly on the try-on makeup;
/// if it is shifted, the points do not match the photo's pixels.
struct FeedbackPointCheck: View {
    @ObservedObject var store: MakeupFlowStore
    let feedback: MakeupFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Developer: points on the photos").font(.caption.weight(.semibold))
            HStack(alignment: .top, spacing: 8) {
                panel("Expected", photo: store.desired, scan: store.desiredScan, target: store.desiredScan.map(Self.changed) ?? [])
                panel("Result", photo: store.result, scan: store.resultScan, target: feedback.marks.flatMap(\.target))
            }
            Text(verbatim: "white: mesh · cyan: eyes · pink: target. Pink should sit on the makeup.")
                .font(.caption2.monospaced())
        }
        .foregroundStyle(AppColors.onboardingBody)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Points (0...1 on the photo) whose colour the virtual makeup changed by more than 8 ΔE.
    static func changed(_ scan: FaceScan) -> [CGPoint] {
        scan.samples.indices.filter { i in
            let s = scan.samples[i]
            guard s.visible, let shown = s.rendered else { return false }
            return simd_distance(shown, s.lab) > 8
        }.map(scan.photoPoint)
    }

    @ViewBuilder private func panel(_ title: String, photo: UIImage?, scan: FaceScan?, target: [CGPoint]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(title): \(scan == nil ? "no scan" : "\(target.count) target")").font(.caption2.monospaced())
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(photo.size, contentMode: .fit)
                    .overlay {
                        Canvas { context, size in
                            func dot(_ p: CGPoint, _ r: CGFloat, _ color: Color) {
                                let c = CGPoint(x: p.x * size.width, y: p.y * size.height)
                                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                            }
                            if let scan {
                                for i in stride(from: 0, to: scan.samples.count, by: 25) where scan.samples[i].visible {
                                    dot(scan.photoPoint(i), 0.6, .white.opacity(0.7))
                                }
                            }
                            for p in target { dot(p, 0.8, .pink.opacity(0.8)) }
                            if let scan {
                                for eye in [scan.leftEye, scan.rightEye].compactMap({ $0 }) {
                                    dot(CGPoint(x: eye.x / max(scan.viewport.width, 1), y: eye.y / max(scan.viewport.height, 1)), 2.5, .cyan)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(verbatim: "no photo").font(.caption2.monospaced())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

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
                        tag("Expected", dot: false)
                        Spacer()
                        tag("Result", dot: true)
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
                    if let photo, case let marks = feedback.marks(for: first), !marks.isEmpty {
                        // Nothing found: only where it should go; there is nothing to add to or wipe off yet.
                        FixCrop(photo: photo, marks: first.rule.hasSuffix(".none")
                                ? marks.map { .init(side: $0.side, target: $0.target, add: [], remove: []) } : marks)
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

/// -Nimah: the result photo cropped to the fix, with dashed outlines instead of dots (device test 2026-11-10: filled dots
/// hid the cheek and read as blush): white = the try-on area, pink = where to add, pink with a light fill = what to wipe
/// off. Each outline is an ellipse fitted to that group of mesh points, with stray points left out.
private struct FixCrop: View {
    let photo: UIImage
    let marks: [MakeupFeedback.Mark]
    static let aspect: CGFloat = 2.2

    /// The outlines, in photo points.
    private var shapes: (target: [Oval], add: [Oval], remove: [Oval]) {
        func ovals(_ pick: (MakeupFeedback.Mark) -> [CGPoint], minimum: Int, unlessMostOfTarget: Bool = false) -> [Oval] {
            marks.compactMap { mark in
                let points = pick(mark)
                // "Add here" over most of the target says nothing new: the target outline and the message tell it.
                if unlessMostOfTarget, points.count * 10 > mark.target.count * 7 { return nil }
                guard points.count >= minimum else { return nil }
                return Oval(points.map { CGPoint(x: $0.x * photo.size.width, y: $0.y * photo.size.height) })
            }
        }
        return (ovals(\.target, minimum: 6), ovals(\.add, minimum: 8, unlessMostOfTarget: true), ovals(\.remove, minimum: 8))
    }

    var body: some View {
        let shapes = self.shapes
        let rect = Self.crop(shapes.target + shapes.add + shapes.remove, photo: photo.size)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let size = proxy.size
                let scale = size.width / max(rect.width, 1)
                Image(uiImage: photo)
                    .resizable()
                    .frame(width: photo.size.width * scale, height: photo.size.height * scale)
                    .offset(x: -rect.minX * scale, y: -rect.minY * scale)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .overlay {
                        Canvas { context, _ in
                            let place = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
                                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                            let dash = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
                            let pink = AppColors.dandanPink
                            for oval in shapes.target {
                                context.stroke(oval.path.applying(place), with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 3.5, dash: [6, 5]))
                                context.stroke(oval.path.applying(place), with: .color(.white), style: dash)
                            }
                            for oval in shapes.remove {
                                context.fill(oval.path.applying(place), with: .color(pink.opacity(0.18)))
                                context.stroke(oval.path.applying(place), with: .color(pink), style: StrokeStyle(lineWidth: 2))
                            }
                            for oval in shapes.add { context.stroke(oval.path.applying(place), with: .color(pink), style: dash) }
                        }
                    }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 14) {
                legend(Circle().stroke(AppColors.onboardingBody, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])), "Your try-on area")
                if !shapes.add.isEmpty {
                    legend(Circle().stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])), "Add here")
                }
                if !shapes.remove.isEmpty {
                    legend(Circle().fill(AppColors.dandanPink.opacity(0.2)).overlay(Circle().stroke(AppColors.dandanPink, lineWidth: 1.2)), "Wipe off")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo of the area to fix")
    }

    private func legend(_ shape: some View, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            shape.frame(width: 10, height: 10)
            Text(title).font(.system(size: 11)).foregroundStyle(AppColors.onboardingBody)
        }
    }

    /// The part of the photo (points) around the outlines, padded, at `aspect`, kept inside the photo.
    static func crop(_ ovals: [Oval], photo: CGSize) -> CGRect {
        let box = ovals.map(\.path.boundingRect).reduce(CGRect.null) { $0.union($1) }
        guard !box.isNull, photo.width > 0, photo.height > 0 else { return CGRect(origin: .zero, size: photo) }
        var w = max(box.width * 1.4, photo.width * 0.3), h = max(box.height * 1.4, 1)
        if w / h < aspect { w = h * aspect } else { h = w / aspect }
        if w > photo.width { h *= photo.width / w; w = photo.width }
        if h > photo.height { w *= photo.height / h; h = photo.height }
        let x = min(max(box.midX - w / 2, 0), photo.width - w), y = min(max(box.midY - h / 2, 0), photo.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// An ellipse round a group of points: their spread (two standard deviations along the main axes), after dropping points
/// far from the rest (more than 2.5 times the median distance from the median point).
struct Oval {
    let center: CGPoint
    let radii: CGSize
    let angle: CGFloat

    init(_ all: [CGPoint]) {
        func median(_ v: [CGFloat]) -> CGFloat { let s = v.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }
        let mid = CGPoint(x: median(all.map(\.x)), y: median(all.map(\.y)))
        let distances = all.map { hypot($0.x - mid.x, $0.y - mid.y) }
        let limit = max(median(distances) * 2.5, 1)
        let points = zip(all, distances).filter { $0.1 <= limit }.map(\.0)
        let n = CGFloat(max(points.count, 1))
        let c = CGPoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
        var xx: CGFloat = 0, yy: CGFloat = 0, xy: CGFloat = 0
        for p in points { let dx = p.x - c.x, dy = p.y - c.y; xx += dx * dx; yy += dy * dy; xy += dx * dy }
        xx /= n; yy /= n; xy /= n
        let mean = (xx + yy) / 2, spread = ((xx - yy) * (xx - yy) / 4 + xy * xy).squareRoot()
        center = c
        radii = CGSize(width: max(2 * (mean + spread).squareRoot(), 4), height: max(2 * max(mean - spread, 0).squareRoot(), 4))
        angle = 0.5 * atan2(2 * xy, xx - yy)
    }

    var path: Path {
        Path(ellipseIn: CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2))
            .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
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
