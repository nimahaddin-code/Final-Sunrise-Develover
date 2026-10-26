import SwiftUI

/// Stand-ins for the iPhone app's design tokens (which come from its asset catalog), so the shared `ScanOverlayView` compiles here.
enum AppColors {
    static let rose = Color(red: 0.84, green: 0.36, blue: 0.48)
    static let subtle = Color.secondary
}

enum AppSpacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let cornerRadius: CGFloat = 24
}
