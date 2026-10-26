import SwiftUI
import UIKit

/// The "done" confirmation drawn out of the Dynamic Island, in the style of the system's App Store and Apple Pay confirmation.
///
/// Apps cannot use that system animation, and iOS hides an app's own Live Activity from the island while the app is open, so this
/// draws it: a black shape placed exactly over the hardware island grows into a rounded square, a green check draws itself, then
/// the shape shrinks back behind the island. It lives in its own window above the status bar so it covers the clock like the system
/// one, and it never takes touches.
@MainActor enum DynamicIslandConfirmation {
    /// The hardware island in window coordinates, or `nil` on iPhones without one. iOS has no API for this, so it is estimated from
    /// the top safe area: island models report 59 pt or more (notch models 47 to 50 pt), and the island sits 48 pt above that edge.
    static func islandFrame(in window: UIWindow) -> CGRect? {
        let top = window.safeAreaInsets.top
        guard top >= 51 else { return nil }
        let size = CGSize(width: 125, height: 37)
        return CGRect(x: (window.bounds.width - size.width) / 2, y: max(top - 48, 10), width: size.width, height: size.height)
    }

    static var isAvailable: Bool { keyWindow.flatMap(islandFrame(in:)) != nil }

    private static var window: UIWindow?

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?.keyWindow
    }

    /// Plays the confirmation. `onCheck` runs as the check starts drawing, which is where the sound and haptic belong.
    /// Returns `false` (and does nothing) on iPhones without a Dynamic Island.
    @discardableResult
    static func show(onCheck: @escaping @MainActor () -> Void) -> Bool {
        guard let host = keyWindow, let scene = host.windowScene, let island = islandFrame(in: host) else { return false }
        window?.isHidden = true

        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .statusBar + 1
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        let controller = UIHostingController(rootView: IslandConfirmationView(island: island, onCheck: onCheck) {
            if window === overlay { window = nil }
            overlay.isHidden = true
        })
        controller.view.backgroundColor = .clear
        overlay.rootViewController = controller
        overlay.isHidden = false
        window = overlay
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Scan complete"))
        return true
    }
}

private struct IslandConfirmationView: View {
    let island: CGRect
    let onCheck: @MainActor () -> Void
    let onFinish: @MainActor () -> Void

    /// Size of the expanded square, as in the system confirmation.
    private let expandedSide: CGFloat = 150
    @State private var expanded = false
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Starts a little smaller than the hardware island so it is hidden behind it, and ends there again.
        let collapsed = island.insetBy(dx: 3, dy: 2).size
        let size = expanded ? CGSize(width: expandedSide, height: expandedSide) : collapsed
        ZStack(alignment: .topLeading) {
            Color.clear
            RoundedRectangle(cornerRadius: expanded ? 44 : collapsed.height / 2, style: .continuous)
                .fill(.black)
                .overlay {
                    CheckmarkCircle()
                        .trim(from: 0, to: drawn)
                        .stroke(Color(red: 0.6, green: 0.96, blue: 0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .frame(width: 76, height: 76)
                        .opacity(expanded ? 1 : 0)
                }
                .frame(width: size.width, height: size.height)
                .position(x: island.midX, y: island.minY + 2 + size.height / 2)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func run() async {
        let grow: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.72)
        withAnimation(grow) { expanded = true }
        try? await Task.sleep(for: .seconds(0.28))
        onCheck()
        withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.5)) { drawn = 1 }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.9)) { expanded = false }
        try? await Task.sleep(for: .seconds(0.5))
        onFinish()
    }
}

/// A circle and a check inside it, as one path: trimming it draws the circle first, then the check.
struct CheckmarkCircle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
        path.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.02))
        path.addLine(to: CGPoint(x: center.x - radius * 0.1, y: center.y + radius * 0.34))
        path.addLine(to: CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.34))
        return path
    }
}

#Preview {
    CheckmarkCircle()
        .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        .frame(width: 76, height: 76)
        .padding(40)
        .background(.black)
}
