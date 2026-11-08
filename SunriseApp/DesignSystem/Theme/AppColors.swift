import SwiftUI

enum AppColors {
    static let background = Color("Canvas")
    static let rose = Color("Rose")
    static let ink = Color("Ink")
    static let card = Color("Card")
    static let subtle = Color("Subtle")

    // Try On home palette: #660033, #5F2C30, #F5477D, #FFFFFF.
    static let wine = Color(red: 0x66 / 255, green: 0x00 / 255, blue: 0x33 / 255)
    static let cocoa = Color(red: 0x5F / 255, green: 0x2C / 255, blue: 0x30 / 255)
    static let flamingo = Color(red: 0xF5 / 255, green: 0x47 / 255, blue: 0x7D / 255)
    static let snow = Color.white
    /// Camera and tutorial caption fill (UX spec 1.1), #370B21.
    static let captionFill = Color(red: 0x37 / 255, green: 0x0B / 255, blue: 0x21 / 255)
    /// Warm white of the screen light's glow around the camera (#FFF4EA).
    static let ringLight = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xEA / 255)
    /// Full-screen background of the Try On, tutorial and palette screens (black; wine stays for pills and accents).
    static let screen = Color.black
    /// Tint of the standard glass controls over the camera (smoky wine, so white icons stay readable on bright pictures).
    static let glassBase = Color(red: 0x66 / 255, green: 0x00 / 255, blue: 0x33 / 255).opacity(0.38)
    /// Tint of a chosen glass control: the design's raspberry (#C41E5A) behind the white ring.
    static let glassSelected = Color(red: 0xC4 / 255, green: 0x1E / 255, blue: 0x5A / 255).opacity(0.9)
    /// Tint for a flamingo (#F5477D) glass button: glass lifts the tint towards white, so the tint is a step deeper
    /// (#CC3F6B) and the rendered button lands on the design's #F5477D-looking pink.
    static let glassAction = Color(red: 0xCC / 255, green: 0x3F / 255, blue: 0x6B / 255)
    /// Pink of the "Go to Tutorial" button as it renders in the design (#EC2A6B, deeper than the design swatch because glass milks the colour).
    static let prepPink = Color(red: 0xEC / 255, green: 0x2A / 255, blue: 0x6B / 255)
    /// Fill of the tutorial's raised bottom-bar buttons (#8D1F44).
    static let raisedWine = Color(red: 0x8D / 255, green: 0x1F / 255, blue: 0x44 / 255)
    /// Background of the add-colour sheet: the design's raspberry wine (#8B1C42).
    static let sheet = Color(red: 0x8B / 255, green: 0x1C / 255, blue: 0x42 / 255)
    /// Tint of an unchosen style circle over the camera: near white, so the dark picture on it reads (#FFF1F5).
    static let glassPale = Color(red: 0xFF / 255, green: 0xF1 / 255, blue: 0xF5 / 255).opacity(0.78)
    /// Tint of the pale mauve add-colour button and the start of the intensity track (#D9A6BD).
    static let glassLight = Color(red: 0xD9 / 255, green: 0xA6 / 255, blue: 0xBD / 255).opacity(0.6)
    /// Page background of the feature homepage (#FFFBF8).
    static let homeCanvas = Color(red: 0xFF / 255, green: 0xFB / 255, blue: 0xF8 / 255)
    /// Page background of the brow Try On, the brow card's tint (#FAF2EA).
    static let browCanvas = Color(red: 0xFA / 255, green: 0xF2 / 255, blue: 0xEA / 255)
    /// Dark plum text and the selected page dot on the feature homepage (#2A1A20).
    static let plumInk = Color(red: 0x2A / 255, green: 0x1A / 255, blue: 0x20 / 255)
    /// Brand pink of the "dandan" wordmark and the active onboarding dot (#FF2D8E).
    static let dandanPink = Color(red: 0xFF / 255, green: 0x2D / 255, blue: 0x8E / 255)
    /// Headings on the light onboarding pages (#111111).
    static let onboardingInk = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    /// Body text on the light onboarding pages (#6B6B6B).
    static let onboardingBody = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x6B / 255)
    /// Dark capsule buttons: onboarding and the homepage (#1C1C1C).
    static let buttonInk = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255)
}

/// Full-screen burgundy page background: the `main-bg` asset over wine.
struct MainBackground: View {
    var body: some View {
        AppColors.wine.overlay {
            Image("main-bg").resizable().scaledToFill()
        }
        .clipped()
        .ignoresSafeArea()
    }
}
