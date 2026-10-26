import SwiftUI

/// The confirmation shown over the camera when a scan finishes: a black rounded square with a green circled checkmark, like the
/// system's "done" HUD. It pops in with a success tap. Colours are fixed on purpose: it must read on top of any camera picture.
struct ScanDoneBadge: View {
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.black)
            Image(systemName: "checkmark.circle")
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(Color(red: 0.6, green: 0.96, blue: 0.55))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .sensoryFeedback(.success, trigger: true)
        .accessibilityElement()
        .accessibilityLabel("Scan complete")
    }
}

#Preview {
    ScanDoneBadge().padding(40).background(.gray)
}
