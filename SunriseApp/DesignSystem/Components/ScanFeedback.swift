import ActivityKit
import SwiftUI
import UIKit

/// Runs the scan's Live Activity. iOS shows it in the Dynamic Island and on the Lock Screen only while the app is *not* open,
/// so it covers someone who leaves mid-scan; the "done" confirmation inside the app is `DynamicIslandConfirmation`.
@MainActor final class ScanActivityController {
    private var activity: Activity<ScanActivityAttributes>?
    private var lastStep = -1
    /// Updates run one after another, so a late "progress" never lands after "done".
    private var queue: Task<Void, Never>?

    func update(title: String, progress: Double, isDone: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let step = isDone ? 100 : Int(progress * 20) * 5
        guard step != lastStep else { return }
        lastStep = step
        let state = ScanActivityAttributes.ContentState(progress: isDone ? 1 : progress, isDone: isDone)
        let content = ActivityContent(state: state, staleDate: nil)

        if activity == nil, !isDone {
            activity = try? Activity.request(attributes: ScanActivityAttributes(title: title), content: content, pushType: nil)
        } else if let activity {
            let previous = queue
            queue = Task {
                await previous?.value
                if isDone {
                    await activity.end(content, dismissalPolicy: .immediate)
                } else {
                    await activity.update(content)
                }
            }
            if isDone { self.activity = nil }
        }
    }

    /// Ends the activity right away, such as when the person leaves the screen.
    func end() {
        guard let activity else { return }
        self.activity = nil
        lastStep = -1
        let previous = queue
        queue = Task {
            await previous?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func reset() { lastStep = -1 }
}

private struct ScanFeedbackModifier: ViewModifier {
    let title: String
    let progress: Double
    let isDone: Bool
    @State private var controller = ScanActivityController()

    func body(content: Content) -> some View {
        content
            .onChange(of: progress) { _, _ in controller.update(title: title, progress: progress, isDone: isDone) }
            .onChange(of: isDone) { _, done in
                controller.update(title: title, progress: progress, isDone: done)
                guard done else { controller.reset(); return }
                let confirm = {
                    ScanDoneSound.play()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                // Out of the Dynamic Island when there is one; otherwise the scan screen shows `ScanDoneBadge` and this just confirms.
                if !DynamicIslandConfirmation.show(onCheck: confirm) { confirm() }
            }
            .onDisappear { controller.end() }
    }
}

extension View {
    /// Keeps the scan's Live Activity current and, when `isDone` turns true, plays the done confirmation: the check out of the
    /// Dynamic Island with its sound and haptic.
    func scanFeedback(title: String, progress: Double, isDone: Bool) -> some View {
        modifier(ScanFeedbackModifier(title: title, progress: progress, isDone: isDone))
    }
}
