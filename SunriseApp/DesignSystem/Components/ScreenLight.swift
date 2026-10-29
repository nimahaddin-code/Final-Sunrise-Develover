import SwiftUI
import UIKit

/// The camera screens' "light": the front camera has no flash, so the screen itself lights the face. On, the screen goes
/// to full brightness and a warm glow frames the camera (`ScreenLightGlow`); off, her own brightness comes back.
/// Leaving the screen restores the brightness; `suspend()`/`resume()` do the same for the app going to the background
/// and bring the light back on return.
@MainActor final class ScreenLight: ObservableObject {
    @Published private(set) var isOn = false
    private var savedBrightness: CGFloat?

    func toggle() { isOn ? turnOff() : turnOn() }

    func turnOn() {
        isOn = true
        apply()
    }

    func turnOff() {
        isOn = false
        restore()
    }

    /// Restores the brightness but remembers the light was on (background, call, lock screen).
    func suspend() { restore() }

    /// Turns the brightness back up if the light was on.
    func resume() { if isOn { apply() } }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private func apply() {
        guard let screen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = 1
    }

    private func restore() {
        guard let saved = savedBrightness else { return }
        screen?.brightness = saved
        savedBrightness = nil
    }
}

/// Warm white ring-light frame around the camera preview while the screen light is on.
struct ScreenLightGlow: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(AppColors.ringLight, lineWidth: 24)
            .blur(radius: 4)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The round, raised wine button of the camera screens' bottom bar (compare, light).
struct CameraBarButton: View {
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(AppColors.snow.opacity(0.9))
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [AppColors.snow.opacity(0.14), AppColors.snow.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom))
                        .background(AppColors.wine, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                }
                .overlay(Circle().strokeBorder(AppColors.snow.opacity(0.12), lineWidth: 1))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}
