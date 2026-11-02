// -Nimah: LookArtwork.swift — implementasi MVP SunriseApp.
import SwiftUI

struct LookArtwork: View {
    let referenceID: String
    static func color(for id: String) -> Color {
        switch id {
        case "sculpted-glam": return Color(red: 0.66, green: 0.35, blue: 0.28)
        case "clean-girl": return Color(red: 0.87, green: 0.47, blue: 0.40)
        case "soft-glam": return Color(red: 0.65, green: 0.28, blue: 0.41)
        case "latte": return Color(red: 0.65, green: 0.39, blue: 0.25)
        default: return Color(red: 0.89, green: 0.31, blue: 0.49)
        }
    }
    var body: some View {
        Group {
            if referenceID == "sculpted-glam" {
                Image("GlamReference").resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 280)
                    .background(AppColors.card).clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    .accessibilityLabel("Selected glam reference: bronze cheeks, brown eyes and rose-brown lips")
            } else { illustratedFace }
        }
    }
    @ViewBuilder private var illustratedFace: some View {
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

// -Nimah: Sketsa edukasi terpisah dari foto referensi dan kamera; tidak menyimulasikan hasil pada user.
struct PlacementDiagram: View {
    let step: TutorialStep
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            LookArtwork(referenceID: "soft-glam")
                .overlay {
                    Canvas { context, size in
                        for point in PlacementDots.targets(for: step) {
                            let center = CGPoint(x: size.width / 2 + CGFloat(point.x) * 900, y: 95 - CGFloat(point.y) * 850)
                            let rect = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
                            context.fill(Path(ellipseIn: rect), with: .color(.white))
                            context.stroke(Path(ellipseIn: rect), with: .color(AppColors.rose), lineWidth: 1.8)
                        }
                    }.accessibilityHidden(true)
                }
            Text("Placement sketch · approximate starting points").font(.caption).foregroundStyle(AppColors.subtle)
        }.accessibilityElement(children: .combine).accessibilityLabel("Approximate dotted placement sketch for \(step.title)")
    }
}
