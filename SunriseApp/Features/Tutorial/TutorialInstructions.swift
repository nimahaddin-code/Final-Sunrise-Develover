// -Nimah: TutorialInstructions.swift — implementasi MVP SunriseApp.
enum TutorialInstructions {
    static func text(for step: TutorialStep, referenceID: String) -> String {
        let all: [String: [String]] = [
            "douyin": ["Tap rosy blush high on the cheeks and blend softly toward the temples.", "Blend a light contour below the cheekbones. Keep the edges soft.", "Sweep rose shadow across the lid; add a small touch of shimmer at the center.", "Draw a fine wing from the outer corner in short strokes.", "Tap rose color at the center of the lips and blend the edges."],
            "clean-girl": ["Apply a sheer peach blush and blend upward on the cheeks.", "Use very little contour and blend until no hard line remains.", "Wash the lids with a soft neutral beige.", "Press brown liner close to the upper lashes.", "Finish with a sheer rosy balm."],
            "soft-glam": ["Build muted rose blush in thin layers over the cheeks.", "Blend contour from the ears toward the cheekbones.", "Blend taupe into the crease, then add soft shimmer to the lid.", "Create a small lifted wing with brown liner.", "Outline softly and fill with rose nude lipstick."],
            "latte": ["Sweep warm terracotta blush over the cheeks.", "Blend warm contour around the cheeks and hairline.", "Layer caramel and bronze shadows across the lid.", "Smudge brown liner gently along the upper lashes.", "Apply caramel nude lip color and a touch of gloss."]
        ]
        let index = TutorialStep.allCases.firstIndex(of: step) ?? 0
        return (all[referenceID] ?? all["douyin"]!)[index]
    }
}
