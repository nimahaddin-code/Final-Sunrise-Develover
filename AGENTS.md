## Feedback: Expected / Result, dashed outlines, nothing found told on both cards — -Nimah (2026-11-10)

Device test: no blush worn gave Placement 1% "Spot on" and "Blush placement is right", and the crop filled both cheeks
with pink dots that also sat on the lids, nostrils and lip corners. Now: a rule ending in `.none` is told on both cards and
no praise is shown while anything is missing (`FeedbackComposer.assemble`); "left and right match" still goes when a fix
is for one side. `FixCrop` draws dashed ellipses (`Oval`: two standard deviations of the points, strays past 2.5x the
median distance left out) per side: white = "Your try-on area", pink dashed = "Add here" (only when the bare part is less
than 70% of the target), pink line with a light fill = "Wipe off". The blush mark keeps only cheek points (beside the nose,
below the eyes, within 1.6 radii of the target). `MakeupFeedback.marks(for:)` returns one mark per side. The slider's
tags are "Expected" / "Result" (id "Target" / "Hasilmu"). "your both cheeks" reads "both your cheeks". Simulator tests and
a synthetic render only; not checked on a device.

