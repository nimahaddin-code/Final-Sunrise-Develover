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
}
