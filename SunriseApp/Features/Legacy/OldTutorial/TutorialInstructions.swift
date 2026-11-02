// -Nimah: TutorialInstructions.swift — implementasi MVP SunriseApp.
enum TutorialInstructions {
    static func text(for step: TutorialStep, referenceID: String) -> String {
        let all: [String: [String]] = [
            // -Nimah: Breakdown visual manual dari foto referensi, bukan output AI analysis.
            "sculpted-glam": [
                "Use a peach-bronze blush. Place a little product along the high cheek dots, then blend upward toward the temples. Keep the center of the cheeks softly diffused. Finish with a small touch of highlight above the blush.",
                "Use a neutral brown contour just below the cheekbones. Follow the lower cheek dots from the ears inward, stopping before the mouth. Blend upward. The small nose dots are a starting guide: use very little product and soften both sides of the bridge.",
                "Blend a warm taupe-brown shadow over the lid and into the crease. Deepen the outer corner with cocoa brown, soften the edges, then add a small champagne highlight near the inner corner. The dots mark approximate skin areas, not an exact eyelid outline.",
                "Apply a thin dark-brown or black line close to the upper lashes. Start at the outer corner and extend a small lifted wing following the outer guide dots. Keep the line fine, then finish with mascara. Adjust the wing to your own eye shape.",
                "Choose rose-brown liner and a muted rose-nude lipstick. Follow your natural lip edge with the outline dots as a rough starting point, fill in softly, and blend the liner inward. Refine the outline in a mirror; the guide does not reshape your lips."
            ],
            "douyin": ["Tap rosy blush high on the cheeks and blend softly toward the temples.", "Blend a light contour below the cheekbones. Keep the edges soft.", "Sweep rose shadow across the lid; add a small touch of shimmer at the center.", "Draw a fine wing from the outer corner in short strokes.", "Tap rose color at the center of the lips and blend the edges."],
            "clean-girl": ["Apply a sheer peach blush and blend upward on the cheeks.", "Use very little contour and blend until no hard line remains.", "Wash the lids with a soft neutral beige.", "Press brown liner close to the upper lashes.", "Finish with a sheer rosy balm."],
            "soft-glam": ["Build muted rose blush in thin layers over the cheeks.", "Blend contour from the ears toward the cheekbones.", "Blend taupe into the crease, then add soft shimmer to the lid.", "Create a small lifted wing with brown liner.", "Outline softly and fill with rose nude lipstick."],
            "latte": ["Sweep warm terracotta blush over the cheeks.", "Blend warm contour around the cheeks and hairline.", "Layer caramel and bronze shadows across the lid.", "Smudge brown liner gently along the upper lashes.", "Apply caramel nude lip color and a touch of gloss."]
        ]
        let index = TutorialStep.allCases.firstIndex(of: step) ?? 0
        return (all[referenceID] ?? all["douyin"]!)[index]
    }
}
