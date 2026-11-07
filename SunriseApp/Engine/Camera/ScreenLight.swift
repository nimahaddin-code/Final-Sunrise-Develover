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
    /// True: Apple's plain glass and label colour while off, instead of the app's wine glass and white icon.
    var plainGlass = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Button { light.toggle() } label: {
            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .modifier(LightGlass(on: light.isOn, plain: plainGlass))
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

/// The round, raised wine button of the tutorial's bottom bar (compare, light), drawn as in the design: a flat #8D1F44
/// disc with fine noise, a soft white inner shadow on its left rim and a dark drop shadow to the right. No glass.
struct CameraBarButton: View {
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppColors.snow)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(AppColors.raisedWine)
                        .overlay { RaisedNoise().clipShape(Circle()) }
                        .overlay {
                            // Inner shadow: only the thin crescent the disc leaves when shifted 2 pt to the right.
                            Circle().fill(Color.white.opacity(0.24))
                                .mask {
                                    Rectangle().overlay { Circle().offset(x: 2).blendMode(.destinationOut) }
                                        .compositingGroup()
                                }
                                .blur(radius: 1.5)
                                .clipShape(Circle())
                        }
                        .shadow(color: .black.opacity(0.42), radius: 1.5, x: 3, y: 0)
                }
                .padding(6)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

/// Fixed fine speckle (black and white at 25%), the design's duo noise. Drawn once from a seeded sequence, so it never shimmers.
private struct RaisedNoise: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) & 0xFFFF) / 65535
            }
            for i in 0..<70 {
                let dot = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                context.fill(Path(ellipseIn: dot), with: .color((i % 2 == 0 ? Color.black : Color.white).opacity(0.16)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The light button's surface: white glass with a pink bolt while on; off, the app's wine glass with a white bolt, or
/// Apple's plain glass with the label colour (`plain`).
private struct LightGlass: ViewModifier {
    let on: Bool
    let plain: Bool

    func body(content: Content) -> some View {
        if on {
            content.glassCircle(tint: AppColors.snow.opacity(0.7))
                .foregroundStyle(Color(red: 0.96, green: 0.28, blue: 0.49))
        } else if plain {
            content.glassEffect(.regular.interactive(), in: .circle).foregroundStyle(.primary)
        } else {
            content.glassCircle().foregroundStyle(AppColors.snow)
        }
    }
}
