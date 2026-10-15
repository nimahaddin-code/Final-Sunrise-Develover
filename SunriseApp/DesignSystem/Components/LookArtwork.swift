// -Nimah: LookArtwork.swift — implementasi MVP SunriseApp.
import SwiftUI

struct LookArtwork: View {
    let referenceID: String
    static func color(for id: String) -> Color {
        switch id {
        case "clean-girl": return Color(red: 0.87, green: 0.47, blue: 0.40)
        case "soft-glam": return Color(red: 0.65, green: 0.28, blue: 0.41)
        case "latte": return Color(red: 0.65, green: 0.39, blue: 0.25)
        default: return Color(red: 0.89, green: 0.31, blue: 0.49)
        }
    }
    var body: some View {
        let color = Self.color(for: referenceID)
        ZStack {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius).fill(color.opacity(0.12))
            Ellipse().fill(Color(red: 0.28, green: 0.17, blue: 0.16)).frame(width: 118, height: 150)
            Ellipse().fill(Color(red: 0.93, green: 0.75, blue: 0.63)).frame(width: 94, height: 124).offset(y: 7)
            HStack(spacing: 24) { ForEach(0..<2) { _ in Capsule().fill(Color.black.opacity(0.75)).frame(width: 16, height: 3) } }
            HStack(spacing: 35) { ForEach(0..<2) { _ in Ellipse().fill(color.opacity(0.65)).frame(width: 26, height: 16).blur(radius: 4) } }.offset(y: 24)
            Capsule().fill(color).frame(width: 24, height: 6).offset(y: 46)
            Image(systemName: "sparkles").font(.title).foregroundStyle(color).offset(x: 68, y: -48)
        }.frame(height: 190).accessibilityLabel("Makeup placement illustration")
    }
}
