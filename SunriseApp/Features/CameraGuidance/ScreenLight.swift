import SwiftUI
import UIKit

/// The "light" on the front camera: the screen itself. On sets the brightness to full and shows a warm ring around the
/// preview; off puts back the brightness she had. Leaving the camera screen or the app turns it off, and coming back
/// turns it on again if it was on.
@MainActor final class ScreenLight: ObservableObject {
    @Published private(set) var isOn = false
    private var savedBrightness: CGFloat?
    private var wasOnWhenSuspended = false

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen
    }

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        guard let screen else { return }
        if on {
            savedBrightness = screen.brightness
            screen.brightness = 1
        } else if let savedBrightness {
            screen.brightness = savedBrightness
            self.savedBrightness = nil
        }
    }

    /// The camera screen is leaving or the app is going away: restore the brightness and remember the state.
    func suspend() {
        wasOnWhenSuspended = isOn
        set(false)
    }

    /// The camera screen is back: light up again if it was on before.
    func resume() {
        if wasOnWhenSuspended { set(true) }
        wasOnWhenSuspended = false
    }

    /// Leaving for good: the light stays off on return.
    func turnOff() { wasOnWhenSuspended = false; set(false) }

    static let glow = Color(red: 1, green: 0xF4 / 255, blue: 0xEA / 255)
}

/// The ring-light frame drawn inside the camera card.
struct ScreenLightGlow: View {
    @ObservedObject var light: ScreenLight
    var cornerRadius: CGFloat = AppSpacing.cornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(ScreenLight.glow, lineWidth: 24)
            .blur(radius: 3)
            .opacity(light.isOn ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: light.isOn)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The light button. `pulse` changes each time the "too dark" message appears, to show her where it is.
struct ScreenLightButton: View {
    @ObservedObject var light: ScreenLight
    var pulse: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Button { light.toggle() } label: {
            Image(systemName: light.isOn ? "sun.max.fill" : "sun.max")
                .font(.title3)
                .frame(width: 52, height: 52)
                .background(AppColors.wine.opacity(0.75), in: Circle())
                .foregroundStyle(light.isOn ? ScreenLight.glow : AppColors.snow)
                // Reduce Motion: a pink outline instead of a pulse.
                .overlay(Circle().strokeBorder(AppColors.flamingo, lineWidth: 3).opacity(pulsing && reduceMotion ? 1 : 0))
                .scaleEffect(pulsing && !reduceMotion ? 1.25 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Light")
        .accessibilityValue(light.isOn ? "On" : "Off")
        .onChange(of: pulse) { _, _ in
            withAnimation(.easeOut(duration: 0.35)) { pulsing = true }
            Task {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 1500 : 450))
                withAnimation(.easeIn(duration: 0.3)) { pulsing = false }
            }
        }
    }
}
