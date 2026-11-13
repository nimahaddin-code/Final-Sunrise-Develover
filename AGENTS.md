## Feedback measured on the photo's own frame; developer point check — -Nimah (2026-11-12)

The photos are no longer matched to a scan pose, so the feedback relies on the ARKit mesh being read on the picture it
compares. At the shutter three moments were mixed: the photo and the virtual-makeup colours came from the frame the engine
drew, the face mesh and skin colours from `session.currentFrame` after the read-back finished (a frame or more later), and
the eyes / pose for the slider from the pose tracker's last reading. A head or phone that moved in between put the points
beside the makeup. Now `copyForReaders` hands the shutter the `ARFrame` it drew (`ScreenShot`: pixels + frame) and
`FeatureCaptureView.shoot` measures `FaceScan`, the eyes and `CapturePoseReading` on that frame; without the engine's
picture it falls back to the live frame as before. The developer read-out says `frame same` or `frame live`. Still not on
the same frame: the eyeliner target on Expected (drawn by SwiftUI from the live tracking).

Developer tools on the feedback screen add `FeedbackPointCheck`: both photos with a sparse mesh grid (white), eye centres
(cyan) and the target (pink: on Expected the points the virtual makeup changed by more than 8 ΔE, on Result the marks'
targets). Pink should sit on the try-on makeup. Test `testPointCheckMarksTheVirtualBlush`; 382 Simulator tests pass. Not
checked on a device.

## Lips: fourth tool (card, three lipstick shapes, tutorial) — Khalish (2026-11-11)

`TryOnTool.lips` runs through the same one-tool flow as the others. Home: a fourth card on the right (order Eyeliner, Blush,
Brows, Lips; `home-card-lips`). Try On: `LipsTryOnFeature` (`Features/Lips/TryOn/`) lists three shapes, `LipStyle`: Natural
(the person's own lip line), Full (past the lip line in the middle, `LipShape.fullReach` = 3.5% of the mouth's width,
nothing at the corners) and Gradient (strong in the middle, 30% at the edge); five shades (`MakeupPalette.lipShades`,
approximate, not product colours) plus the colour sheet and the intensity bar. Drawing: a 2D overlay like the eyeliner.
`LipOverlayModel` (`Features/Lips/Engine/`) sends ARKit's frames to its own `MediaPipeEyeLandmarkProvider`, which now also
returns the lips (`EyeLandmarkFrame.lips`: outer edge and mouth opening, 20 points each, MediaPipe's FACEMESH_LIPS), carries
the newest result with the head on every frame and publishes it in view points; `LipShape` turns it into the fills that
`LipOverlayView` (live) and `LipShape.compose` (the desired-look photo) both draw, normal blending, mouth opening left out.
`LinerFrameRelay` feeds both overlays (`setLipsEnabled`). Tutorial: `TutorialTab.lips`, three steps for every shape
(`GuidedTutorialModel.lipLessons`: mark, connect, fill), one half of the lips then the other like the other tools;
`LipStepGuide` draws the marks, the dashed outline and the pulsing fill on the person's own lips (for Gradient on the middle
of the lips); the steps sheet and the side-done card ("Left side done!") work as before. Not done: lips feedback is not
measured (`MeasuredFeedbackProvider` gives the placeholder, and the feedback screen says "Scores for lips are coming soon"
over the Before / After slider); the kit items have no pictures or popups. Placeholders to replace: `home-card-lips` and
`tutorial-lips-1…3` are drawn by a script, not the design team's art; `LookBriefView.crop` for lips is a guess. New
strings have Indonesian drafts (`needs_review`). 389 Simulator tests pass (new: `LipShapeTests`); the home card, Try On
row, brief and steps sheet were seen on the Simulator (iPhone 17 Pro, iOS 26.5), but it has no camera: the lipstick on a face, its colour and edge, the
head-carry anchors (`LipOverlayModel.mouthAnchors`, rough) and the tutorial guide were never seen and need a device.

## Screen light stays while zoomed, brighter — 2026-11-11

The screen light used to be an inset of the camera picture itself (26 pt plus a 26 pt blur, white page behind), so zooming
the camera zoomed the white edge away. It is now `ScreenLightFrame` (`Engine/Camera/ScreenLight.swift`): a white frame drawn
over the camera, outside the zoom, 64 pt wide with a soft inner edge, so more of the screen is white. Used by the tutorial
(full-bleed card) and Try On (`TryOnLiveCard`). The zoom chip moves in past the frame while the light is on
(`EnvironmentValues.screenLightInset`). The phone brightness was already at full. 380 Simulator tests pass; the look needs a
device.

## Tutorial swipe, bigger step text, compare without the guide; feedback buttons and eye-area slider — 2026-11-11

E2E-Flow was fast-forwarded to staging first (`3f6957d`). Tutorial: a horizontal swipe on the camera moves to the next step
(left) or the previous one (right), within the side being done (`GuidedTutorialView.stepSwipe`; a swipe never finishes a
side or leaves the tutorial). The step instruction over the camera is 19 pt semibold (was 15 medium). The compare button in
the per-side tutorial now takes the guide off: the side being done shows the plain camera and the other side the desired
look (`sideLayout`: `.plainTryOn` / `.tryOnPlain`, were `.guideTryOn` / `.tryOnGuide`), so the eye and brow are not covered
while applying. Feedback: the retake (↻, back to the tutorial) and Done buttons are back at the bottom (the merge had left
`bottomBar` unused); order as design 18: slider, "What we think", ring, the two cards, then the fix-first card. Brows and
eyeliner compare only the eye area in the slider (`FeedbackView.focused`, the brief's `LookBriefView.crop`); blush keeps
the whole face. 380 Simulator tests pass; swipe, compare and the crop need a device. Zoom: with the camera zoomed, the tutorial's Back / Next did nothing: `CameraZoomModifier` scales the camera with
`scaleEffect`, and `.clipped()` only cuts the drawing, so the enlarged camera view kept catching taps over the bottom bar
(and Try On's controls). The scaled content now has `allowsHitTesting(false)`; the pinch stays on the clipped frame.

## Feedback: no marks on the eyes — -Nimah (2026-11-10)

Device test: with no blush worn, "Wipe off" ovals sat on both eyes: lids and lashes change colour between the photos and
read as blush. Blush is now searched below the eyes only (`BlushFeedback.measure`: `y < eyeY - 8` mm), and a "nothing
found" fix shows only the try-on area in the photo crop. The synthetic test face cannot reproduce the lids (its search
area never reached them), so this is checked on a device only.


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

Device feedback: "Far too low" and "3 mm" did not help a beginner. Under the score ring the feedback screen now shows
`FeedbackFixes`: the worst fix in its own card ("Fix this first") with a crop of the result photo (`FixCrop`): the
target as faint pink dots, its bare spots as pink rings ("Add here") and makeup outside it filled ("Wipe off"); then the
next fixes numbered, then "What went well" (the database's praise; "left and right match" is dropped when a fix is for one
side). Each tool records a `MakeupFeedback.Mark` per side (`FaceScan.mark`: target samples and makeup samples on the
result photo, 0...1; blush counts "outside" past the full field), and every message carries its side
(`MakeupFeedback.Item.side`); `MakeupFeedback.fixes` / `mark(for:)` pick them. All 488 numbered sentences of
`makeup-feedback.database.json` (en/id) were rewritten without mm, degrees, percent or "x": guide words instead (blush
"the dotted area" / "area garis putus-putus", brow "the guide", eyeliner "the guide line", strength "than your try-on"),
"a little" in the slight band; the numbers stay in the code for the score and the developer read-out. The category sheet
no longer shows the score database's description (it named millimetres). Test `testNoMessageShowsMeasurements` keeps
numbers out; the crop was seen rendered from a synthetic face only. Not checked on a device.

## Brow filter over the natural brow (eraser off, temporary) — Khalish (2026-11-10)

The natural-brow eraser (`BrowEraser`: push-pull fill + MI-GAN) is switched off for now: `BeautyBlushEngine.configure`
sets `settings.hideNatural=false` whatever `EyebrowConfiguration.hideNaturalBrow` says, so the chosen brow picture is drawn
straight over the user's own brow in Try On, captures and tutorial. Flags, handoff and eraser code are unchanged; restore
with `settings.hideNatural=c.hideNaturalBrow` (comment in place). Not checked on a device.
## Capture back to one oval, shutter always on — 2026-11-10

The strict position for the before and after photos is removed at the team's request: one dashed oval again ("Fit your
whole face inside the line" above the shutter), no face-following outline, green oval, tap, position hints, gaze check or
match to the desired pose, and the shutter works whenever the camera does. Removed: `CaptureHint`, the limits,
`CapturePoseCheck.evaluate` / `match`, `FaceFollowOutline`, `CaptureColors` and their tests. Kept: `CapturePoseTracker`
reads the face in the background so the shutter still records the eyes and mesh points, and the result photo is still
lined up with the desired one for the slider (`FaceHomography`, eye fit fallback). The oval stays 78% of the width. 375
Simulator tests pass.

## Home title "Hi, pretty!" — 2026-11-10

`FeatureHomeView`'s title is "Hi, pretty!" (was "Hi, fellas!"); Indonesian draft "Hai, cantik!" (`needs_review`).

## Navigation buttons that seemed dead — 2026-11-10

A tester found back and continue buttons that did nothing. Code check of every route's buttons (`AppRootView.destination`):
the wiring was right, three things stopped the taps. Try On's back was a `Button` with a simultaneous 1.2 s long press
(developer tools); on iOS 26 that gesture can swallow the tap. It is now one gesture, `LongPressGesture.exclusively(before:
TapGesture)`, with button traits and an accessibility action. Try On's Continue is disabled until a look is on, but looked
the same as enabled: it now reads "Pick a look to continue" and dims. The tutorial's steps sheet still opens by itself at the start (by
design), over the bottom bar until it is closed. The tutorial's back
still steps back one step and leaves only from the first step. 379 Simulator tests pass; the taps were not checked on a
device (the Simulator cannot get past Try On without a camera).

## Merge: staging (onboarding animations, feedback Before fix) into E2E-Flow — 2026-11-10

staging brought Khalish's onboarding animations and Nimah's feedback fixes (Before = the try-on photo, directional card
notes, `PhotoAlignment` by the eyes). One code conflict, the Before / After slider: Before is now staging's
`store.desired ?? store.bare`; After prefers E2E-Flow's mesh-aligned `store.alignedResult`, then staging's eye-aligned
picture, then the photo as taken. Strings: staging's catalog plus 14 E2E-Flow keys. 379 Simulator tests pass.

## Tutorial step pictures — 2026-11-10

`TutorialStepsSheet` shows the design team's stills instead of grey boxes: image sets `tutorial-brow-1…4` (brush up with the
spoolie, map from the nose, connect and fill, blend and clean up), `tutorial-liner-1…3` (dots, dashed line, filled liner)
and `tutorial-blush-1` (dashed circle), 339 x 226 PNGs, shown full width at that shape. `TutorialStepsSheet.imageName(tab:step:)`
maps a lesson to its picture (`Step.imageName`; the grey box stays for a missing one). `GuidedFlowTests` checks every lesson
has its picture. Simulator tests only; the sheet was not opened on a device.

## Before and after photos in one fixed position; result lined up by the eyes — 2026-11-10

Both captures (`FeatureCaptureView`, desired and result) now need the same fixed position, so the Before / After slider
compares like with like. `CapturePoseTracker` reads the shared ARKit session about 15 times a second;
`CapturePoseCheck.read` projects an ellipse on the face (`CapturePoseCheck.face`, metres) with the makeup engine's projection,
so `FaceFollowOutline` follows the head in 3D, and measures the off-axis angle (face forward vs camera), the eye line's roll
and the eyes. `CapturePoseCheck.evaluate` asks, in this order: outline width within 8% of the oval (`CapturePoseCheck.oval`,
also drawn by `FaceOvalGuide`), centred within 6% / 5% of the oval, off-axis under 6°, roll under 5° (looser values to stay
in: no flicker), and otherwise gives one `CaptureHint` ("Move a little closer", "Turn your face a little to the left",
"Lift your chin a little", ...; mirrored-picture directions). In position: the oval and hint turn green, the phone taps,
and the shutter works only then. At each shutter the eyes are kept
(`MakeupFlowStore.eyes`); the result photo is turned, scaled and moved so its eyes sit on the desired photo's
(`EyePair.align`, skipped when the change would be over 25% or 15°) and the slider shows `alignedResult`. The measured
feedback still uses the unaligned scans. All limits and the outline size are untuned guesses: tune on a device. New hint
strings are not in the catalog yet. 374 Simulator tests pass (new: position checks, eye alignment); the camera parts need
a device. Device round 1: the two photos still looked in different directions, so the eyes must now look into the camera
(`CapturePoseReading.gazeDegrees` from `ARFaceAnchor.lookAtPoint`, under 10°; hint "Look at the camera, at the top of the
screen"), the head limit is tighter (off-axis 4°), there is no auto-capture (the person takes the photo; the shutter still
works only in position; hint "Perfect, take the photo"), and the oval is a little smaller (68% of the screen width, was
78%), so the face sits a bit farther away. Device round 2 (still a visible difference): fixed limits are tighter (off-axis and roll 3°, size 5%, centre 4% / 3.5%,
gaze 8°), and the result photo must also match the desired photo's own pose (`MakeupFlowStore.poses`,
`CapturePoseCheck.match`: head turn on all axes within 2.5° of it (quaternion angle), distance within 3%, face centre within
2.5% of the oval), since two photos each inside the fixed limits could differ by twice them. The oval turns green only
after 3 readings in a row pass (`steadyReadings`, about 0.2 s), so one noisy ARKit frame cannot pass. Device round 3: 68% was too far to hold the phone steady; 74% was tried too; the oval is back to 78% of the screen width. Device round 4 (easy to reach, exact result): the result photo is now lined up through the face mesh, not only the eyes:
each shutter keeps every 6th ARKit face-mesh vertex on screen (`CapturePoseReading.meshPoints`, same index = same skin in
both photos) and whether it faces the camera; `FaceHomography` fits a perspective map from the result's points to the
desired photo's (least squares over about 200 points, normalised DLT) and redraws the result through it
(`CIPerspectiveTransform`; skipped when a corner would move over 20%), which also takes out a few degrees of turn and nod;
the eye fit is the fallback. So the live limits are easier again (off-axis and roll 5°, size 8%, centre 6% / 5%, gaze 10°;
match to the desired pose 4°, 6%, 5%). The hint pill moved to the top, under the back / style / light row.
## Feedback Before = the try-on photo — -Nimah (2026-11-10)

Device test: the slider's Before showed the bare face. Before is now the try-on photo taken at the desired-look shutter
(`MakeupFlowStore.desired`, the virtual makeup on); After (the result) is lined up with it (`PhotoAlignment`, eyes from
`desiredScan`). The bare camera (`bare`) stays only as the fallback when there is no try-on photo. Not checked on a device.

## Merge: Hanum's latest E2E-Flow into staging — -Nimah (2026-11-10)

E2E-Flow (design sizes for brief, item sheet and feedback; Done at the bottom; two `FeedbackCategory` cases; eyeliner photo
in points and normal blending; tutorial guides kept on their side; camera messages only while the face is lost) merged
with staging's directional card notes and lined-up Before/After. `FeedbackView` is Hanum's layout; her `BeforeAfterSlider`
now shows the lined-up After photo (`alignedResult`). `FeedbackCategory.isShade` is `self == .shade`. 372 Simulator tests
pass; not checked on a device.

## Feedback cards say which way; Before / After lined up — -Nimah (2026-11-09)

As in the design: each card's note says which way it is off, from its worst message (`FeedbackNote`: "A little high", "Too
heavy", "Far too short", or a phrase such as "Past the line", "Gaps to fill"; "Spot on" with no message; the score database
label when a rule has no word), and the line beside the ring is built from the two cards, good first ("Your shade is spot
on. Placement is a little high."). Coverage (gaps in the target) is told under Placement, since it follows where the makeup
went. The slider's After photo is lined up with the bare Before photo (`PhotoAlignment`): each shutter records the eye
centres on screen (`FaceScan.leftEye` / `rightEye`), and the result is moved, scaled and turned so its eyes land on the
Before photo's eyes (left as it is beyond 1.6x or 25°). Tests in `BlushFeedbackTests`. Not checked on a device.

## Merge: staging (score database, brow colour) into E2E-Flow — 2026-11-10

staging brought Nimah's score database (`makeup-score.database.json`, Placement and Shade percentages with a label and a
description shown in the card's sheet), the brow colour check, and her merge of an earlier E2E-Flow. Conflicts resolved:
`FeedbackView` keeps E2E-Flow's latest layout (design sizes, Done, no Photo tips) and gains the sheet's description;
`MakeupFeedback` keeps staging's `Category.description` and `Part` / `placement` / `shade`; `FeedbackComposer`'s score groups
use E2E-Flow's two-case `FeedbackCategory` (`[.placement]`, `[.shade]`, the same rule priorities as staging's six groups),
and the fallback `shade` part reads `.shade` (was `.finish`). Strings: staging's catalog plus 32 E2E-Flow keys. 370
Simulator tests pass; not checked on a device. Feedback screen: the share button is gone from the top bar (back and the look's name only); the app has no way left to
share or save the result photo from this screen.

## Feedback cards: Placement and Shade only; brief and popup to the design; eyeliner photo position — 2026-11-09

`FeedbackCategory` has two cases (design 18): `placement` (rule priorities 20-39 where and what shape, 50-59 spill, 70+
balance) and `shade` (under 20 nothing applied, 40-49 amount, 60-69 finish and hue); the six database groups are folded
into them, so the feedback screen shows two cards. `LookBriefView` follows the design again: title "Your expected result",
larger type, an item with a popup reads as a link (pink, solid pink underline; no ⓘ). `KitItemSheet` is a native sheet:
system material, a `NavigationStack` inline title with a close button in the toolbar, system padding, the picture on a
white card, the text, and "Got it" as a large `.glass` button; the kind label and the tip are no longer shown.
Eyeliner capture: `ARSCNView.snapshot()` returns a scale-1 image (one point per pixel) while the liner is drawn in view
points, so the liner landed small in the top left; the snapshot now gets the view's size in points
(`FeatureCaptureView.inPoints`). Tutorial: the camera now runs from the top edge under the status bar (`GuidedTutorialView.fullBleed`, rounded only above
the bottom bar; buttons stay in the safe area); brow step 4 reads "Blend the front and clean up." Eyeliner colour: the liner is now laid over the camera with normal blending, live and in the photo (`LinerOverlayView`,
`LinerOverlayRenderer.compose`); multiplied into skin, every liner shade (all dark: brown, plum, navy, black) read as black. Second design pass: brief and feedback use the design's sizes (brief: title 28 expanded black, photo 362:196, "What to
prepare" 22 bold, labels 12/11 semibold, card name 17 semibold, rows 15, details 13, 36 pt icon circles, grey style pill
12 semibold; feedback: headline 32 expanded black, subtitle 15, Before/After 362:236 with small tags, score card 17/13,
categories 11 semibold, percent 20 bold rounded, bottom ↻ and "Done" (home; sharing stays the top button, "Save look"
removed)). Item sheet: the product photo fills a full-width card at its own 1086:588 shape; close and "Got it" in ink.
`SideDoneCard`'s second button is now "Done", which ends the tutorial without the other side (result photo, or the photo
screen outside the flow); "Replay left …" and `GuidedTutorialModel.replaySide()` are gone. Third pass: the feedback screen no longer shows the "Photo tips" card (its text also showed an unfilled {value}). Brief:
KEEP NEARBY lists two items (micellar water and cotton pads/buds; "Clean, dry face" removed from `TryOnTool.nearby`),
text uses only #0A0A0A and #757575 (link names in ink with a pink underline), the light `StylePill` is 154 x 40, and
"Start tutorial" is a native `.glassProminent` button tinted `AppColors.buttonInk` with a drop shadow. Tutorial side guides on a turned face: the blush guide now draws only the cheek on its side, picked by the cheeks' own
positions (`BlushTutorialOverlay(side:)`; the screen-half mask `FaceHalfMask` is gone), the blush split for the pigment
follows the nose (5.5 cm forward of the face anchor) instead of the anchor's origin inside the head, and the brow guide
shows a lone visible brow only when it is on its side. The eyeliner already splits between the two eyes. Camera messages: `CameraAdvisor` shows a message only while the face is not tracked (or the phone is too hot), so the
filter and guide stay on while ARKit follows the face (head down, dim light, backlight, close or far). The message still
names the likely reason (too dark, backlit, too close, turned away, covered: `CameraMessageEngine.lostCause` now also
blames a face last seen covered; "I'll wait here" / "I can't see you yet" only when no reason is known). "Too dark" still
pulses the light button. "Start tutorial" is back to 52 pt high (glass tint on a fixed-height label). 365 Simulator tests pass; the brief, popup and eyeliner photo were not looked at after
this change (Simulator has no camera; brief and popup not opened), device check pending.

## Merge: staging into E2E-Flow — 2026-11-09

staging (Nimah's measured feedback for every tool, capture diagnostics, the Indonesian rewrite, the blush kit data)
merged into E2E-Flow. `FeedbackView` is staging's redesign (measured categories, Before / After with the bare photo);
E2E-Flow's own feedback restyle and `MakeupFeedback.Part` were dropped. `FeatureCaptureView` keeps E2E-Flow's layout
(oval, style pill, shutter) with staging's shutter logic (`FaceScan`, `CaptureDiagnostics`, bare photo, blush target
`cameraConfiguration`). `LookBriefView` and the brief items (`TryOnTool.mustHave` / `nearby`) stay E2E-Flow's, so the
blush kit from `BlushInfo` (`ToolInfo.kitItems`, `TryOnTool.kit`) no longer shows on the brief; its test was replaced by
one that checks the brief's item pictures exist. Strings: staging's catalog plus E2E-Flow's 43 new keys (English only,
no Indonesian for those yet). 365 Simulator tests pass; nothing checked on a device.

## Tutorial, side-done card, steps sheet and feedback restyle — 2026-11-09

Follows the design (tutorial screens, 17 After photo, 18 Your feedback). `GuidedTutorialView` (one-tool flow): black page,
camera card with 28 pt corners; over it compare (left, glass), `StylePill` and the screen light (right); at its bottom the
step's instruction (white, shadow) and step dots. Bottom bar: back circle, "Tutorial" (opens the steps sheet), Next /
Finish (Finish on the last step of each side). Finish on the first side shows `SideDoneCard` over a blurred camera
("Left cheek/brow/eye done!", "Do my right …" = `advance()`, "Replay left …" = `GuidedTutorialModel.replaySide()`). The
side done first (`.leading`) is now called "Left", as the design names it. Step copy from the design's list: brows 4
steps, blush 1, eyeliner 3; `FaceGuideLesson.title` is the short step title (sheet), `instruction` the text over the
camera; the encouragement lines and the second-side cheer are gone. The guide overlays get `GuidedTutorialModel.guideStep`
(`browGuideSteps` = brush, dots, fill, front; `blushGuideSteps` = both outlines), so the brow overlay's clean-up step and
the blush inner-circle-only step are no longer shown. `TutorialStepsSheet`: white, "Tutorial" with close, compact height
(`TutorialStepsSheet.compact`) shows the current step and "Swipe for more", large shows all with Done / Now / Up next;
step pictures are grey placeholders. `FeedbackView`: light page, back (home), style name, share; "Nice work!", try-on vs
result under a drag divider (`CompareSlider`, labelled Try-on / Yours, not the design's Before / After, since there is no
bare photo), overall ring, Placement and Shade cards (`MakeupFeedback.placement` / `shade`, "—" and "Coming soon" while
nil, as the placeholder provider returns), retry (back to tutorial) and "Save look" (the share sheet; nothing is saved by
the app). The result capture uses the same hint as the first. Photo mode (tutorial without the flow) is unchanged. New
strings not synced into the catalog. Simulator only (no camera there): layout seen, guides on a face need a device check.

## Before photo, "Your final look" brief and item popups — 2026-11-08

Restyled to the design (screens 09, 10, 10a/10b). `FeatureCaptureView` (both stages): full-page camera, back, the style
pill (`StylePill`: shade dot + `styleTitle`, shared with the brief) and the screen light in the top safe area, a dashed
white oval for the whole face (`FaceOvalGuide`; replaces the per-feature frame, `FeatureFrameOverlay`/`FeatureFrameShape`
and `TryOnTool.captureRegion`/`captureHint` deleted), the hint pill and a white ring shutter; Retake + dark glass Next
once taken. `LookBriefView`: light page on `OnboardingGlow`, "Your final look" (black, expanded width), the desired photo
cropped to the feature (`LookBriefView.crop`, placeholder fractions), "What to prepare", MUST HAVE cards and KEEP NEARBY ·
FOR MISTAKES rows, dark "Start tutorial". Items come from `TryOnTool.mustHave` / `nearby` (`MakeupKitItem` with `kind` and
optional `info`; replaces `kit`); an item with `info` shows a dotted pink underline and ⓘ and opens `KitItemSheet`
(kind, name, picture, text, sparkle tip, "Got it"). Pictures: the design team's product photos in `kit-blush`,
`kit-fluffy-brush`, `kit-liquid-liner`, `kit-micellar-water`, `kit-spoolie`, `kit-brow-pencil` (the last two replace the
SVG Repo drawings); a missing picture falls back to the item's SF Symbol. New strings are not yet synced into `Localizable.xcstrings` (no Indonesian). Simulator only (iPhone 17
Pro): brief and popup seen with a sample photo, capture seen in its no-camera state; the crop and oval need a device check.
## Feedback cards scored with the score database — -Nimah (2026-11-09)

The feedback screen now has the design's two cards, Placement and Shade, scored with `makeup-score.database.json` (now in
the app target; `FeedbackDatabase.load()` also loads it as `scores`). Each tool records its raw differences per side
(`ScoreInputs`): blush offset (hypot of up and out, mm) and area ratio / hue and strength; brow mean offset of head, tail and
arch (mm) and arch height / hue, darkness and thickness; eyeliner mean offset of start, wing reach and tip (mm) and wing angle
(not Natural) / darkness and thickness. Nothing applied on a side: 1% for both. `ScoreDatabase.score` uses the database's
curve (0 -> 100, ok -> 90, slight -> 75, clear -> 55, 2x clear -> 20, 3x clear -> 1; mm thresholds x IPD/63), averages the
sides, takes the weighted mean of the metrics, and the card shows that percentage's label; the sheet opens with its
description, then the advice messages (placement, shape, spill and balance rules under Placement; amount and finish under
Shade). Overall ring = mean of the two cards; Hanum's `placement` / `shade` parts follow them. Without the score database the
per-group cards remain. Tests: `BlushFeedbackTests`, `LineFeedbackTests`. Not checked on a device.


## Score database: what each Placement and Shade percentage means — -Nimah (2026-11-09)

`SunriseApp/Resources/makeup-score.database.json` (draft; read by the app since the entry above): for blush, brow and
eyeliner, the Placement score (from the Try On coordinates: the target drawn on the desired-look photo against the result on
the same ARKit mesh points, mm) and the Shade score (colour, strength and thickness against the Try On look and the chosen
shade) each get 100 entries, 100% down to 1%: band, short label and a description (formal Indonesian and English) naming
the single difference that gives that percentage (e.g. blush placement 61% = centre about 8.8 mm off, or area 1.85x). One
curve for every metric: 0 -> 100, ok -> 90, slight -> 75, clear -> 55, 2x clear -> 20, 3x clear -> 1, thresholds from
`makeup-feedback.database.json`; a category = weighted mean of its metrics. Generated by
`Tools/Feedback/make_score_database.py`: change thresholds or wording there and run it again. Not yet wired to the feedback
screen's cards (they use the rule bands today). To read it: `Docs/SkorPlacementShade.html` (opens in any browser; pick
tool, Placement or Shade, ID or EN, and a percentage), written by the same script from `Tools/Feedback/score_page_template.html`.

## Brow colour check — -Nimah (2026-11-09)

`BrowFeedback` now checks the colour (`brow.hue.warmer` / `cooler`): the darkest quarter of the product samples inside the
target (where the pencil covers most and skin between hairs least), light-matched, against the chosen brow shade
(`LineFeedbackInput.shade`, from `handoff.shades[.eyebrow]`). Redder or more orange than the shade (a smaller hue angle for
browns) is "warmer", towards grey-yellow "cooler"; below chroma 4 the colour is not read. Database thresholds (12/22/35°).
Lands in the Finish card. `LineFeedbackTests` (chosen shade, red-brown, ashy). Simulator tests only.

## Merge: Hanum's E2E-Flow restyle with the measured feedback — -Nimah (2026-11-09)

`E2E-Flow` (Hanum: before photo, "Your final look" brief and item popups, tutorial, side-done card, steps sheet and feedback
restyled to the design) merged with staging (measured feedback, PRs #1-#7). Layout follows Hanum's files; on top of them:
the capture keeps measuring (`cameraConfiguration`, `measuresBlushTarget`, screen read-back, `FaceScan`, diagnostics, bare
photo). `FeedbackView` is Hanum's with the measured data: headline from the score, Before (bare) / After in her
`CompareSlider` when a bare photo exists (else Try-on / Yours), the summary line, one card per measured category in her card
style (`partCard`) that opens `FeedbackCategorySheet`, the retake cards when a photo check blocked, photo tips and the
developer read-out. `FeedbackComposer.assemble` also fills her `placement` / `shade` parts (placement and finish categories).
The get-ready kit is Hanum's (`mustHave` / `nearby` with the design team's photos); the `BlushInfo` kit and its `kitItems`
are no longer shown there (test `testEveryKitItemPictureIsInTheAssets` checks her pictures). Her 42 new strings got
Indonesian drafts in the brand voice. Simulator tests only.

## Feedback screen redesign; capture diagnostics; stricter blush detection — -Nimah (2026-11-09)

`FeedbackView` follows design "18 · Your feedback": light theme (`OnboardingGlow`), top bar (back = Done, "Blush ·
Sunkissed", share), headline from the score (Perfect! / Nice work! / Almost there! / Let's try again!; "Retake the photo"
when a photo check blocked), Before / After with a drag slider (`BeforeAfterSlider`; Before = the bare camera kept at the
desired-look shutter, `MakeupFlowStore.bare`), score ring with the database's label and a short line (the two weakest
categories), and "What we think" cards (`MakeupFeedback.Category`, from `FeedbackCategory`: the database's priority groups
placement, shape, amount, clean edges, finish, balance; each with its own score, label and messages, shown in a sheet when
tapped). Bottom: ↻ back to tutorial, "Save look" = share sheet with the After photo (Save Image puts it in the person's own
photos; the app keeps nothing). Photo notes that did not block show as "Photo tips". New texts have Indonesian drafts.
Second device test: the result photo still had SceneKit guide shapes and the desired photo no virtual blush. The capture now
uses `EyebrowConfiguration.measuresBlushTarget` (engine publishes the outlines, nothing draws them; `showGuide` stays off),
reads the screen with 1.5 s and one retry, and records `CaptureDiagnostics` per shutter (engine, layer, drawing, read result,
target, face), shown under the feedback with developer tools on. Blush detection: chroma rise >= 6 and dE00 >= 5 (database 4
and 3), and each cheek's light is matched on the skin around its field. Simulator: the screen seen with sample data; the
tap-to-open sheet not checked there (taps did not reach the Simulator). Device check pending.

## Feedback photos fixed after the first device test — -Nimah (2026-11-09)

Device test: the desired-look photo had no blush, the result photo showed blush and dotted circles, and the head-tilt
check (8°) blocked every result, so no advice showed. Causes and fixes: `TryOnHomeModel.apply` filtered tools by `canTry`
while the brow model was still loading (`brow.prepare()` is async), which dropped blush on the desired-look capture: it no
longer filters by `canTry` (`layer(_:)` checks it every frame). The result capture runs the blush engine with `showGuide`,
which also makes the SceneKit view under the Metal layer draw guide shapes; `ARSCNView.snapshot()` took those: both
photos are now read from the engine's layer when it is on (`readScreen`). Turned or tilted up to 15°
(`FeedbackPhotoCheck.poseBlockingDegrees`) is now a note, beyond it a retake (database: 8°, blocking). Tests in
`GuidedFlowTests`. Device check of the fix pending.

## Brow and eyeliner feedback measured too — -Nimah (2026-11-09)

`MeasuredFeedbackProvider` now measures every tool (`BrowFeedback`, `EyelinerFeedback` beside `BlushFeedback`; the
placeholder only if the database cannot be read). Every shutter measures the face for every tool; the eyeliner, drawn by
SwiftUI, is read from the composed desired-look picture (`ScreenPixels(image:)`), brows from the engine read-back.
Target = the desired-look photo itself: brow samples at least 12 L* darker than the skin there, liner samples at least 15
L* darker than the bare face (lashes cancel); result = the same in the result photo (`detection.makeup_mask`).
`Engine/Feedback/LineProfile` puts both in a frame along the target line (`LineFrame`, principal axis, inner end first)
and reads the outline per column (`LineProfile`: ends, head/tail heights, arch, rise and fall angles, thickness, darkness);
`FeedbackRecorder` bands values with the database thresholds (IPD-scaled where marked) and builds the messages and score.
Brow: none, head close/far/high/low, tail short/long/high/low, arch inner/outer/high/flat, rise and tail angles, thickness
per third, coverage, darkness (where the brow landed in the target), spill above/below/between the brows (product only:
natural hairs do not count), symmetry, praise. Calibration choice not in the database: when head and tail are both off the
same way, that side's gap, spill and "too light" are not told (the shift is). Eyeliner: none, start early/late, coverage
and thickness per third, too light, smudge above/below, wing angle/length/tip (not for Natural), symmetry, praise.
Not measured: brow head softness, outline, colour; liner lash gap, wobble, blunt or detached wing, Arabian lower line.
Photo checks are shared (`FeedbackPhotoCheck`, per tool: smiling and mouth open for blush, eyes closed for eyeliner,
raised brows for brows); light matching shared (`FeedbackSkin`). Mesh sampling is now 10 points per triangle. Messages
carry their rule id (`MakeupFeedback.Item.rule`). `LineFeedbackTests` (synthetic faces). Not checked on a device.

## Blush feedback v2: measured on the face mesh — -Nimah (2026-11-09)

The E2E feedback screen now measures blush instead of the placeholder text (`AppContainer.feedback` =
`MeasuredFeedbackProvider`; brow and eyeliner: see the section above). At each shutter
`FeatureCaptureView` measures the face (`Engine/Feedback/FaceScan`): six fixed points per ARKit mesh triangle, each with its
face-local position (mm), its bare camera colour (decoded like the shader, Lab), on the desired-look photo also the colour
shown with the virtual blush, its screen point, plus pose, blend shapes and IPD. Stored in `MakeupFlowStore`
(`desiredScan`/`resultScan`, memory only, numbers only). For blush the capture camera publishes the target outlines
(`showGuide`; on the result photo the engine runs with `pigmentHalf = .none`, so the photo stays the plain camera).
`Features/Blush/Feedback/BlushFeedback` compares the two scans sample by sample (same mesh point = same skin, whatever the
pose): light matched on forehead and chin, blush = chroma rise with the shade's hue (`detection.makeup_mask.blush`), then per
cheek against the target (outer line = target area, inner circle = core, outer / 0.82 = limit): none, offset up/down/in/out
(mm, IPD-scaled), size, coverage, strength (vs the virtual blush on the same spots), spill (eye, nose, mouth, ear, jaw),
patchiness, hue; symmetry height, strength and size; praise. Photo checks: no face, turned, tilted, rolled, smiling, mouth
open, too dark, pose and light mismatch, no Try On photo. Bands, texts (id/en, app language), merging, suppression, top 3
and score come from `makeup-feedback.database.json` (now in the app target) through `Engine/Feedback/FeedbackRules`.
Not measured yet: angle, edge softness, Lifted temple reach, Sunkissed nose band, blob cleanup. The desired-look photo now
shows the virtual makeup: `BeautyBlushEngine.readScreen()` copies the next presented drawable (`framebufferOnly` is off),
on both the blush and brow paths; `ARSCNView.snapshot()` had only the camera under the Metal layer. `FeedbackView` lists the
messages as cards in a scroll view. Shared files changed: `BeautyBlushEngine`, `BrowEngine+Draw` (one line), `MakeupFlow`,
`FeatureCaptureView`, `FeedbackView`, `AppContainer`, `project.pbxproj`. `BlushFeedbackTests` (synthetic faces). Thresholds
are the database's draft values; nothing is checked on a device yet (target outline on the result photo, colour detection
in real light, read-back on device).

## Indonesian rewritten in the brand voice — -Nimah (2026-11-09)

Every string the app shows now has Indonesian in the voice of `Docs/GayaBahasa.md` (a big sister who is good at makeup,
"kamu", casual "yuk/aja/nggak", short sentences, makeup terms kept in English): 133 drafts rewritten, the 61 E2E-flow
strings that had none translated (the tutorial's cheers keep their warm tone), and the camera and photo prompts in
`InfoPlist.xcstrings`. Look, shade and style names are unchanged; strings from deleted screens were left alone. All
`needs_review`. Text only; screens not yet checked in Indonesian for longer lines.

## Blush kit on the E2E get-ready page — -Nimah (2026-11-09)

Staging's E2E flow lists the kit from `TryOnTool.kit` (`Features/Screens/Flow/MakeupFlow.swift`); its blush list was a
placeholder. Blush now takes `ToolInfo.blush(...).kitItems`, the `BlushInfo` kit (fingertips, sponge, cream or liquid blush,
loose powder), so it is written in one place. `MakeupKitItem.imageName` (optional) shows the item's picture instead of the
symbol in `LookBriefView`'s card (`kit-blush-*`); brow and eyeliner are unchanged. `BlushInfo`'s look descriptions are not
shown by the E2E flow yet. Simulator tests only.

## Blush look and kit data; kit pictures — -Nimah (2026-11-05)

`BlushInfo` (`Features/Blush/Info/`) is real data now, not sample wording: one beginner sentence per look (Youthful,
Sunkissed, Lifted; other styles get a general one), 1 minute for every look, and one kit for all three: fingertips
(required, symbol), makeup sponge (optional), cream or liquid blush (required, shows the chosen shade; powder or lip tint
as the stand-in) and loose powder (optional). Texts use `String(localized:)`, with Indonesian drafts in `Localizable.xcstrings`
(`needs_review`), written in the brand voice of `Docs/GayaBahasa.md` (casual "kamu", big-sister tone; a prompt to
paste into an AI for new Indonesian copy). Kit pictures: PNG, transparent background, square,
600 x 600, product centred, named `kit-<tool>-<item>` (`kit-blush-sponge`, `kit-blush-blush`, `kit-blush-powder`; brow
`kit-brow-…`, eyeliner `kit-liner-…`). The three blush pictures are flat drawn illustrations, unbranded, to be replaced
by real photos under the same names. `GuidedFlowTests.testEveryItemPictureIsInTheAssets` fails when an `imageName` has
no asset. Simulator tests only.

## Onboarding page art (pages 1-3) — Khalish (2026-11-07)

Page 1 (`artOne`, `OnboardingView.swift`) is now a face photo on the front card with makeup stickers around it; the two cards
behind are blank white (`blankCard`). Image sets: `onb-tryon-1` (face photo, already rounded and rotated 4 degrees clockwise, transparent
corners; the white card behind it takes the same angle), stickers `onb-sticker-brow-1` (thin brow, left), `onb-sticker-brow-2` (thick brow,
top right), `onb-sticker-blush` (used twice, both cheeks), `onb-sticker-lips`. A sticker is drawn only if its image exists (`sticker(_:width:)`),
positioned as a fraction of the card size. `onb-tryon-2` and `onb-tryon-3` were removed.
Pages 2 and 3 pictures are all derived from that one face photo: `onb-step-1` (cheek and mouth corner crop), `onb-step-2` (same kind of crop
with a pink dot on the cheek apple), `onb-step-3` (whole face), `onb-compare-after` (face square crop, with blush), `onb-compare-before`
(same crop, blush reduced by image editing, no code). The "before" is a placeholder, not a real bare-face photo: replace it, and the
other crops, with proper photos when available. Simulator only (iPhone 17 Pro, 17e), no device check.

## One Try On layout for every tool, per-tool `TryOnFeature` — 2026-11-07

`TryOnHomeView` has one layout for all tools, the former brow one: full-page camera, back and light in the top safe area,
palette button, look row (or shades and intensity) and Continue (glass tinted `AppColors.buttonInk`) at the bottom over the
dark gradient that starts right under the palette button (one clear-to-85% ramp, the button itself on the bare camera;
`controlsCard`, `topButtons`). Blush and eyeliner lose the logo header, page padding, light button with dark-scene
pulse and pink Continue, and gain the palette button. The view has no tool branches: a tool adds only its look row and debug
menu through `TryOnFeature` (`Features/Screens/TryOn/TryOnFeature.swift`), implemented in `Features/Blush/TryOn/BlushTryOnFeature`,
`Features/Brow/TryOn/BrowTryOnFeature` and `Features/Eyeliner/TryOn/EyelinerTryOnFeature`; `TryOnTool.tryOnFeature` is the one
switch. New tool: add a `TryOnTool` case, a feature in its folder, and its case in that switch. Developer tools: long-press the
back button (1.2 s; the logo is gone); the "New flow" chip sits under the top buttons while they are on. Simulator build only:
the layout and the eyeliner overlay on the full-page camera are not checked on a device.
Camera off (no TrueDepth, permission denied, camera stopped): `CardMessage` sits on the homepage's `OnboardingGlow` with
`AppColors.plumInk` text; `TryOnLiveCard` reports it (`TryOnCameraOffKey`) so the controls drop the gradient and go
dark-on-light. `GlassPickerRow`'s title now takes the screen's colour (was always white), and the row no longer clips
(`scrollClipDisabled`): the glass "none" circle's shadow, cut at the row's top and bottom, showed as a grey square.
Camera messages: only `CameraGuidanceCaption` (the advisor) shows on Try On, just under back and light
(`TryOnLiveCard(captionTopInset:)` = top safe area + the button row). The old `StatusPill` (engine `beautyStatus`, "Look straight at
the camera to place your makeup") is removed; its string stays in the catalog, unused. Not checked on a device. Seen on the Simulator (blush).

## Merge: E2E-Flow into staging — 2026-11-07

origin/staging (tool-first folders, card-slider home, brow Try On layout, three-page onboarding, Indonesian, `NewFlow`
skeleton) merged with the E2E one-tool flow. Up to home follows staging: splash/onboarding/compact opening behind `NewFlow`
(entry only now), the welcome, then `FeatureHomeView`. After home follows E2E: `tryOn` -> `capture(.desired)` ->
`lookBrief` -> `recommendedTutorial(handoff, attempt:)` -> `capture(.result)` -> `feedback`, always on. Removed from staging:
the placeholder routes `comparison`/`preparation`/`feedback(FeedbackInput)`, `ComparisonView`, `PreparationScreen`, its
`FeedbackView`/`FeedbackInput`/`LookPhoto`, `TutorialPrepView` (E2E's `LookBriefView` replaces it; the `kit-*` image sets stay,
unused), `TutorialHandoff.lookPhoto` and `GuidedTutorialView(onFinish:)` (E2E's `onFinished` + capture screen take the
photo). Removed from E2E: `FeaturePickerView` (staging's home). E2E's flow files moved to `Features/Screens/Flow/`,
`TutorialStepsSheet` to `Features/Screens/Tutorial/`. `TryOnHomeModel(tool:)` takes an optional tool (nil: every tool, as
the tests use); with one, only it reaches the handoff (E2E's `focusTool`). Try On keeps staging's brow layout; every tool now
ends with the pink Continue (to the desired-look photo), and Back goes home. The tutorial bar shows the side and Steps
(per-side, E2E) or the tool's name (staging). Strings: staging's catalog plus E2E's new keys (no Indonesian for those yet).
Simulator build only.

## One-tool E2E flow: home, capture, brief, per-side tutorial, feedback placeholder — 2026-11-05

The app no longer opens on Try On. After the welcome, `FeaturePickerView` (home, "Pick a Feature": Brows / Blush / Liner)
starts a run for one tool: `AppRoute.tryOn(tool)` (`TryOnHomeView` for that tool only, back button, Continue once a style is
on) -> `capture(.desired, handoff)` (`FeatureCaptureView`: camera with the chosen look and the feature's frame, shutter,
Retake/Next) -> `lookBrief(handoff)` (`LookBriefView`: that photo, the style name, what to prepare from `TryOnTool.kit`,
"Go to Tutorial"; replaces `TutorialPrepView`, deleted) -> `recommendedTutorial(handoff, attempt:)` (`GuidedTutorialView`
with `onFinished`: that tool only, every step on the screen's left half (user's right side) then the right half, guide
beside the plain camera, compare toggles the desired look on the other half; `TutorialStepsSheet` opens half height at the
start with its title fixed above the scrolling steps, each step an instruction plus a line of encouragement
(lesson `instruction`, `LinerTutorialStep.cheer`), back up with a cheer when the second side starts; drag up/down or the Steps button; Done pushes the next capture) -> `capture(.result, handoff)` (plain camera, same
frame) -> `feedback(handoff)` (`FeedbackView`: loading with percentage, then feedback; "Back to tutorial" =
`AppNavigator.restartTutorial()`, a new `attempt` from step 1; "Done" returns home). Photos live in `MakeupFlowStore`
(memory only, cleared on Done and on a new pick). Feedback goes through `MakeupFeedbackProviding`
(`AppContainer.feedback`); `PlaceholderFeedbackProvider` waits ~2 s and returns fixed text, it never looks at the photos:
plug the real comparison in there. Placeholders until design: tile icons (SF Symbols), the frame position
(`TryOnTool.captureRegion`; ID-card style cut-out shaped like the feature, `FeatureFrameShape`: one rectangle round both eyes,
two brows or two cheeks, plus corner brackets; nothing checks the feature is inside), kit copy, the steps' GIFs (grey boxes), brief and feedback
layout. Without a usable camera (Simulator) capture offers "Continue without photo" so the flow runs end to end. New files:
`Makeup/Shared/Flow/` (`MakeupFlow`, `FeaturePickerView`, `FeatureCaptureView`, `LookBriefView`, `FeedbackView`) and
`Shared/Tutorial/TutorialStepsSheet`. `TutorialCompare` gained `guidePlain`/`plainGuide` (never in the compare cycle).
Not checked on a device: whether `ARSCNView.snapshot()` includes the Metal blush/brow layer in the desired-look photo.

## New onboarding: light splash and three pages — Khalish (2026-11-06)

`OnboardingWelcomeScreen` (`Features/Onboarding/Welcome/OnboardingView.swift`, rewritten in place, same `onStart`) is now a white page
with a soft pink/grey glow: a splash ("dandan" wordmark + "makeup made for your face", auto-advances after 1.6 s or on tap), then
three pages in one `TabView`: "Try it on before you put it on", "Step by step, at your own pace", "See how you did, side by side"
(button "Get started" calls `onStart`; no Skip). Pictures are image sets to fill with PNGs: `onb-tryon-1` (page 1, see the 2026-11-07 section above), `onb-step-1/2/3`,
`onb-compare-before`, `onb-compare-after` (empty until added; a grey placeholder shows). Tokens: `AppColors.dandanPink`,
`onboardingInk`, `onboardingBody`. The silk image `onboarding-silk` and the old welcome strings were removed; new strings have
Indonesian drafts (`needs_review`). `AppNavigator.currentWelcomeVersion` stays 2. Only the picture swipes; title, text, dots and button stay, the text crossfades and the active dot animates. Simulator only, no device check.

## Brow Try On layout — Khalish (2026-11-06)

Update 2026-11-07: the camera fills the whole page (under the status bar and home indicator) and the palette button, brow pictures
(or shades) and Continue sit at the bottom over a dark gradient (clear to 85% black, no card; `browControlsCard`); back and light stay in the top safe area.
Continue (`.glassEffect` tinted `AppColors.buttonInk`, the homepage button colour) uses system Liquid Glass, like back, light and palette, so the
buttons follow Settings > Display > Liquid Glass (Clear/Tinted); page behind the camera is black.
Brow only (`TryOnHomeView`, `isBrow`): page background `AppColors.browCanvas` (#FAF2EA, dark text), no logo row (so no long-press for developer tools here):
back and the screen light sit over the camera's top corners (`browTopButtons`), no tutorial arrow (`TryOnLiveCard(showsLightButton: false)`, no dark-scene pulse there), a palette
button above `BrowOverlayPicker` swaps it for the shade row and intensity bar inside the camera card (`showsShades`, `shadeControls`; the button turns into an X), and a
"Continue" button at the bottom opens the tutorial like the arrow. Back, light and palette use Apple's plain glass
(`.glassEffect(.regular.interactive())`, `ScreenLightButton(plainGlass:)`); camera messages sit under the top buttons
(`TryOnLiveCard(captionAtTop:)`). All tools: the camera picture's mask now has the card's corner radius (was double, which
left black corners). Blush and eyeliner unchanged. Simulator only.

## Homepage redesign: card slider — Khalish (2026-11-06)

`FeatureHomeView` is now a light page (`AppColors.homeCanvas` #FFFBF8, text `AppColors.plumInk`) with a horizontal card slider in
the order Eyeliner, Blush, Brows, starting on Blush (the others peek in at the sides). The cards are the image sets
`home-card-eyeliner`, `home-card-blush`, `home-card-brows`. Title, step and minute chips, blurb and the three dots follow the
shown card; steps come from `GuidedTutorialModel.*Lessons.count`, minutes from `ToolInfo.minutes`. "Start Lesson" calls
`onSelect` for the shown tool (same route as before: `AppRoute.tryOn(tool)`). New strings have Indonesian drafts
(`needs_review`). Simulator only, no device check.
2026-11-07 restyle: title "Hi, fellas!", background `OnboardingGlow` (shared with onboarding), step and minute chips inside each
card at the bottom left (no chips under the name), active dot `AppColors.dandanPink` (#FF2D8E), dark "Start lesson" button
(`AppColors.buttonInk` #1C1C1C). `AppColors.homeCanvas` is no longer used here.

## Feature homepage, one tool per Try On — Khalish (2026-11-05)

After the welcome the app opens on `FeatureHomeView` (`Features/Screens/TryOn/`): three cards, Blush, Eyeliner, Eyebrow
(`TryOnTool.allCases`), no camera. A card pushes `AppRoute.tryOn(tool)`, which builds `TryOnHomeView(tool:)`; the camera
starts there and stops when going back. Try On has no tool strip any more (back button instead), and
`TryOnHomeModel(tool:)` starts on and `activate()` returns to that tool (`startTool`; default `.eyebrow` for tests), so only
that tool can be switched on and drawn; the tutorial and photo get only it. The model logic is otherwise unchanged and still
supports several tools (`choose(_:)` stays for tests): "one tool" is enforced by the screens, not the model. The tutorial's
tab bar shows the tool's name instead of three tabs (`GuidedTutorialModel.select` stays). New strings have Indonesian
drafts (`needs_review`). Simulator only (homepage, card -> Try On -> back); camera, tutorial and photo need a device check.

## Prep page: brow kit list — Khalish (2026-11-04)

`TutorialPrepView` (`Features/Screens/Preparation/`) shows three cards; "Phone at eye level" is gone. The kit card's `Tip.items`
(`KitItem`: image name + label) lists Spoolie, Brow pencil, Cotton bud, picture left, name right. Pictures are vector image
sets `kit-spoolie` (a mascara wand), `kit-brow-pencil`, `kit-cotton-bud`: CC0 SVGs from one SVG Repo pack, sources in
`Resources/KitImages-SOURCES.txt`. To change an item: edit the `items` array and its image set. Brow only; blush and
eyeliner tools are not listed. Simulator render only, no device check.

## Three-page onboarding — Khalish (2026-11-04)

Superseded by the 2026-11-06 section above.

`OnboardingWelcomeScreen` (`Features/Onboarding/Welcome/OnboardingView.swift`) is now three swipeable pages in one `TabView`: the welcome
(logo, Get Started), "TRY IT ON, LIVE" (blush, brows, eyeliner) and "LEARN IT, STEP BY STEP" (tutorial and photo, photos stay on
the phone), with Next, Skip on pages 2-3, three progress dots, and Start Try On calling `onStart`. The old four dots and scan hint
are gone. `AppNavigator.currentWelcomeVersion` stays 2, so only devices that have not yet dismissed the welcome see it. New strings
are in `Resources/Localizable.xcstrings` with Indonesian drafts (`needs_review`); "Step 1 of 4" and the scan hint were removed.
Simulator only, no device check.

## English and Indonesian — Khalish (2026-11-03)

Two languages: English (source) and Indonesian (`id`). Strings are in `Resources/Localizable.xcstrings`, the camera and
photo-library permission prompts in `Resources/InfoPlist.xcstrings`; `knownRegions` has `id`. The Indonesian was drafted by AI
and every entry is `needs_review` until a native speaker checks it. Developer-only strings (eye debug readout, brow debug
menu, format-only keys such as `%lld`) are `shouldTranslate: false`. New UI text: write English in code with `Text("...")` or
`String(localized:)`; an enum title that returns `String` must use `String(localized:)`, or it is never translated. Shade names come
from `makeup-reference.database.json` and are manual catalog keys (`extractionState: manual`): add a key when adding a palette.
`xcodebuild` does not write new keys back into the catalog: build in Xcode, or run
`xcrun xcstringstool sync SunriseApp/Resources/Localizable.xcstrings --stringsdata <the build's .stringsdata files>` and
check the diff. Test with the scheme's App Language or `-AppleLanguages (id)`. Simulator only, no device check.

## Tool-first folders: Features/Blush, Brow, Eyeliner, Screens — -Nimah (2026-11-03)

Files moved, no code, flow or UI change. Each tool is at the top of `Features/`: `Blush/`, `Brow/`, `Eyeliner/`, each with
`TryOn/`, `Engine/`, `Tutorial/`, `Info/`. Screens that show all tools are in `Features/Screens/`: `TryOn/` (was
`Makeup/Shared/Home`), `Comparison/`, `Preparation/`, `Tutorial/`, `Feedback/`. What works behind the screens joined the
top-level `Engine/`: `Camera/`, `Rules/`, `Info/` (`ToolInfo`), and `FaceData/` (was `Makeup/Shared/Support`: face and eye
shape types still in use). `Features/Onboarding/` is unchanged. Owners: Blush and Feedback Nimah; Brow and Onboarding
Khalish; Eyeliner and the other Screens Hanum; `App/`, `Engine/`, `DesignSystem/`, `Resources/` shared (tell the group
first). Paths in older notes: `Makeup/<Tool>/` is now `Features/<Tool>/`, `Makeup/Shared/...` as listed here.

## Guided flow, Phase 0: skeleton behind a switch — -Nimah (2026-11-03)

The new flow (splash, onboarding, compact opening, comparison, preparation, feedback) exists as placeholder screens,
already wired, behind `NewFlow` (`App/NewFlow.swift`, UserDefaults `dandan.newFlow`, off by default). Switch it on with
developer tools (long-press the logo) -> "New flow" chip on Try On: the screens after Try On follow at once, the entry
screens from the next launch. Off, the app is exactly as before. Work split and order: the team page "Pembagian Kerja
Dandan". Placeholders use `FlowPlaceholder` (DesignSystem, English developer text, replace the whole view).

- Entry (Khalish): `Features/Onboarding/` now has `Splash/SplashView`, `Pages/OnboardingPagesView` (2 pages),
  `CompactOpening/CompactOpeningView`, run by `EntryFlowView`; the existing welcome moved to `Welcome/OnboardingView.swift`.
- After Try On (Hanum): routes `AppRoute.comparison` -> `.preparation` -> `.recommendedTutorial` -> `.feedback`.
  `Makeup/Shared/Comparison/ComparisonView`, `Makeup/Shared/Preparation/PreparationScreen` (wraps `TutorialPrepView`, moved
  here). `TutorialHandoff.lookPhoto` (memory only) is for the Try On photo, nil until that button exists.
- Feedback (Nimah): `Makeup/Shared/Feedback/FeedbackView`, input `FeedbackInput` (handoff + result photo).
  `GuidedTutorialView(onFinish:)` hands the result photo over on Done instead of closing.
- Per-tool data: `ToolInfo` (`Makeup/Shared/Info/`: look name, description, `minutes`, tools and products; each `Item` has
  name, detail, alternative, symbol, `required` (false: nice to have), `imageName` (asset instead of the symbol) and
  `showsShade` (product card shows the chosen shade)) is
  filled by each tool in `Makeup/<Tool>/Info/` (`BlushInfo`, `BrowInfo`, `EyelinerInfo`, sample wording to replace);
  `ToolInfo.chosen(in:)` gives the tools that are on. Field rules and examples: the team page "Data Alat dan Produk".
- `BlushLookPicker` (`Makeup/Blush/TryOn/`) is the blush look row moved out of `TryOnHomeView`, unchanged.
Tests: `GuidedFlowTests` (331 pass). Seen on the Simulator: the splash; the rest checked by tests only, not on a device.

## Unused code deleted — -Nimah (2026-11-02)

Checked by building, not guessed: everything in `Features/Legacy/` was deleted, then the app and tests were built and
any file still needed was put back. Kept and moved to `Makeup/Shared/Support/`: `EyeScan` (`EyeShape`, used by
`EyelinerPlanner`), `FaceShape`, `FaceProportions`, `FaceContourMeasurer`, `FaceMeshMeasurer`, `EyeMeasurer`,
`EyeScanLandmarks`, `FaceFeatureMap`, `FaceFit`; `ScanDebugOrientation` (`AppOrientationDelegate`, portrait lock) to `App/`.
Deleted: face/eye scan screens and classifiers, Scan Debug, `SunriseDebugMac/` (its tab was gone), old try-on and tutorial,
Profile, catalog/import/saved looks, comparison, calibration, mocks, `PreviewSupport`, unused design components, the
`.sunrisescan` type in Info.plist, `mediapipe-canonical-face.json` and its licence, images `AppIcon test`, `logo-grey`,
`brow-overlay-3`. `AppRoute` keeps only `recommendedTutorial`; `AppContainer` only `faceTracking`; the old scan
`OnboardingView` is gone (`OnboardingWelcomeScreen` stays). `MockFaceTrackingChecker` moved to the tests' `ServiceStubs`.
Tests of deleted code were deleted (423 -> 327); two Try On/tutorial tests now build their plan with `MakeupPlan(shape:)`
as the app does, and three navigation tests use the tutorial route. No flow or UI change.

## Folders per tool: Makeup/<Tool>/{TryOn,Engine,Tutorial}, Legacy — -Nimah (2026-11-02)

Files moved, no code, flow or UI change. Live code is under `Features/TryOn/`, one folder per tool, each with `TryOn/`
(what the Try On screen shows: pickers, looks, config), `Engine/` (what draws it on the camera) and `Tutorial/` (steps,
animations); `Shared/` holds what the tools share: `Home/` (Try On screen, live card, palette), `Camera/` (LiveGuide,
CameraGuidance, `DeviceFaceTrackingChecker`, `TrackingReadiness`), `Tutorial/` (`GuidedTutorialView` shell, prep page,
photo), `Rules/` (rule database, `MakeupPlan`, recommendation types), `Support/` (five files from the old scan/try-on that
live code still uses: `FaceContourDetector`/`SendablePixelBuffer`, `FaceShapeClassifier`/`FaceShapeResult`,
`EyeShapeResult`, `EyeDebugView`/`DeveloperTools`, `MakeupTextureRenderer`; their own dependencies still live in Legacy).
`Core/Engine/` keeps the shared engine (`BeautyBlushEngine`, `BeautyBlush.metal.txt`, `MediaPipeBrowTracker`).
`Features/Legacy/` holds what the app no longer reaches, kept, not deleted: `Scan/` (FaceShape, EyeShape), `ScanDebug/`,
`OldTryOn/` (old try-on screen and renderer, `EyebrowOverlayView`, `ProfileView`, `BlushMask`, `BlushPlacementSketch`),
`OldTutorial/`, `Reference*`, `SavedLooks/`, `Comparison/`, `FaceCalibration/`, `BlushComparison/` (orphans, not in the
project). `Onboarding/` (welcome) stays. `SunriseDebugMac` paths follow. Types keep their names; resources load by bundle
name. Older notes below use the old paths:

Split, no logic change (2026-11-02, second commit): each tool's tutorial is in its `Tutorial/` folder as an extension of
`GuidedTutorialModel` (`BlushTutorial.swift`: `blushLessons` and `BlushTutorialOverlay`, now internal;
`BrowTutorial.swift`: `browLessons`; `EyelinerTutorial.swift`: `linerLessons`, `linerShowsLower`); the shell
(`GuidedTutorialView.swift`: handoff, compare, tabs, per-tab `liveConfiguration`, screen, photo) stays in
`Shared/Tutorial/`. The blush parts of the engine moved from `BeautyBlushEngine.swift` to
`TryOn/Blush/Engine/BlushEngine+Draw.swift` (cheek landmark fit, guide outlines, `bind`, `prepareBlush`, `encodeBlush`), like
the brow's `BrowEngine+*`; `Core/Engine/BeautyBlushEngine.swift` keeps state, setup, configure/submit, `render`, the mask.

Top level and name (2026-11-02, third commit; files only): `Features/TryOn/` is now `Features/Makeup/` (it holds Try On
and tutorial). `SunriseApp/` has five folders: `App/` (entry, root view, container, navigation, `Info.plist`, was
`Configuration/`), `Engine/` (was `Core/AR` + `Core/Engine`, plus `FaceTrackingAvailability` and
`FaceTrackingAvailabilityChecking`), `Features/`, `DesignSystem/` (theme and `GlassKit` only) and `Resources/`.
`Core/Models/Tutorial.swift` moved to `Makeup/Shared/Tutorial/`; the rest of `Core/Models`, `Core/Services/Contracts` and
`PreviewSupport/` went to `Legacy/Scaffold/`, the scan components and `ScanOverlay` to `Legacy/Scan/`, unused components
to `Legacy/DesignSystem/`. `INFOPLIST_FILE` is `SunriseApp/App/Info.plist`. Paths above that say `TryOn/<Tool>` or
`TryOn/Shared` now read `Makeup/<Tool>` and `Makeup/Shared`; `Core/Engine/` reads `Engine/`.

| Old | New |
| --- | --- |
| `Features/TryOnHome/` | `TryOn/Shared/Home/`; brow/liner pickers in their tool's `TryOn/`; prep page in `Shared/Tutorial/` |
| `Features/Tutorial/` | `TryOn/Shared/Tutorial/` (`GuidedTutorialView`, photo); `BrowTutorialOverlay` → `Brow/Tutorial/`, `LinerStepGuide` → `Eyeliner/Tutorial/` |
| `Features/BeautyBlush/`, `Features/Blush/` | shared engine in `Core/Engine/`, blush drawing in `TryOn/Blush/Engine/`; config and placement in `TryOn/Blush/TryOn/` |
| `Features/Eyebrow/`, `Features/Brow/` | `TryOn/Brow/TryOn/` (style, overlays, view model, picker) and `TryOn/Brow/Engine/` (drawing, tracking, eraser, forehead guide) |
| `Features/MakeupTryOn/Eyeliner/` | `TryOn/Eyeliner/Engine/` (with `LinerGeometry`); `EyelinerPlanner` → `Eyeliner/TryOn/` |
| `Features/LiveGuide/`, `Features/CameraGuidance/` | `TryOn/Shared/Camera/` |
| `Features/MakeupPreferences/` | `TryOn/Shared/Rules/` |
| `Features/Forehead/` | `TryOn/Brow/Engine/` |
| `Features/FaceShape/`, `Features/EyeShape/` | `Legacy/Scan/` (except the `Support/` files above) |

## Brow tutorial demo, face-midline split, get-ready page on Try On — 2026-11-02

`BrowTutorialOverlay` (Features/Tutorial) draws the brow tutorial of UX spec 3.4 on the brow outlines the engine publishes
(`BrowGuideFeed`, `BrowEngine.browGuide`): guide outline, three dots, pulsing regions, spoolie/pencil/cotton bud. The
tutorial's split comparison cuts at the face's midline (`FaceSplitFeed`, `BeautyBlushEngine.updateSplit`: nose bridge for brows,
the face anchor for blush, which also scissors the blush pigment), not at the screen's middle. The "get you ready" page is an
overlay of `TryOnHomeView` (`prepHandoff`), no longer the route `tutorialPrep`: replacing a pushed route with the tutorial in one
path update was the suspected cause of the arrow doing nothing after coming back from the tutorial (not reproduced; no device
log). The photo screen's flash now turns on the screen light. Device check pending.

## Brows compare one brow at a time; brow overlay cleanup — Khalish (2026-11-02)

The Brows tab's compare button cycles `BrowCompare` (`.both` → `.left` → `.right` → `.off`), not the split screen. `EyebrowConfiguration.browOnlySide`
(`.subjectLeft`/`.subjectRight`, nil = both brows) makes `drawBrow` draw only that half of the strip index buffer (`BrowEngine+Draw`); `comparisonSplit`
stays false on Brows. `.off` is the plain camera: no hidden natural brow, guide or preview. Blush still cycles the split (`TutorialCompare`).
Removed the eight `brow-sample-1…8` overlays and the `mirrorsForPair` flag: the `supplied.*` PNGs are already head-left/tail-right, so
`browStrip` and the shader no longer mirror them. Simulator build only; device check pending.

## Brow tracker frames via VideoToolbox — Khalish (2026-11-01)

`MediaPipeBrowTracker.bgra(from:)` scales the ARKit YCbCr frame to the 512-long-side BGRA pool buffer with a lazily created
`VTPixelTransferSession` (scaling mode normal, whole source, one call) instead of a Core Image graph per frame. The session lives
on the tracker's serial queue and is invalidated there in `stop()`. If a transfer fails, that frame uses the old `CIContext` render
(still lazy). MediaPipe's `MPImage(pixelBuffer:)` only takes BGRA/RGBA buffers (`MPPImage+Utils.mm`), so a conversion stays
needed. VT uses the buffer's YCbCr matrix attachments and writes the pool buffer's own colour space; no extra colour management.
Simulator build only; device timing and colour match not measured.

## Brow draw loop cleanups — Khalish (2026-11-01)

No behaviour change: the brow's per-frame work is trimmed. Marks use a 3-slot buffer ring like the brow vertices, the developer
menu flags are read at most twice a second, the camera colour attachments are read only when the pixel format or size changes,
and the natural-brow unwrap grid is built only on frames where the eraser's fill is due (`BrowEraser.isDue`). Simulator build only; device check pending.

## Brow split compare in Metal — Khalish (2026-11-01)

The tutorial no longer stacks a second `ARSCNView` (`RealCameraView`, deleted) masked over half the screen. Merged with
staging (2026-11-02): blush halves use staging's `pigmentHalf` (scissor in `render`); this change's `HorizontalEdge`
`comparisonSplit` and `splitScissor` were dropped, and the Brows tab no longer splits (see the top section). Simulator build only;
device look pending.

## Brow: legacy fit off while Metal draws — Khalish (2026-11-01)

When the Metal engine is installed and the configuration is brow-only (`needsBrow`, not blush, not `layered`, not
`showAllRegions`; `LiveGuideView.Coordinator.metalBrowOnly`), the old ARKit/Vision/SceneKit brow path no longer runs: no
`LaunchMakeupFit.fitLive`, `followLaunchFit` or Vision `observe` per frame, `renderEyebrows` hides the anchor node and
returns before copying vertices or taking a pipeline snapshot, and the 0.1 s publish no longer builds a brow snapshot (it
sets `eyebrowWasTracked`/`eyebrowGuideReady` to true once the face is tracked, for the legacy `EyebrowOverlayView`).
Layered/blush/all-regions configurations keep the old behaviour. The ARSCNView drops 4x MSAA once the engine is
installed (kept if it failed, since SceneKit then draws the brow); it stays at 60 fps. Simulator build only; device check pending.

## Eyeliner stretch follow and native Liquid Glass — 2026-10-31

`LidFollower` now starts a pull from the skin's own motion (`skinSpeed`/`skinFrames`), holds it until the followed points and
the detector agree (`stretchRelease`), and pulls back slowly while held (`stretchPullPerResult`); `refresh` + `LinerOverlayModel.refollow`
redraw the followed lid every camera frame. Tutorial and Try On share the model, so guide dots follow too. Benchmark:
`LinerStretchTests`. UI controls use `DesignSystem/Components/GlassKit.swift` (native `glassEffect`; tints `AppColors.glassBase`/
`glassSelected`); the image assets for buttons are gone. Simulator needs iOS 27.0 (target is 26.6); with `xcode-select` on the
Command Line Tools use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Device check pending. See ADR 0018.

## Tutorial brow and eyeliner guides back — -Nimah (2026-10-30)

After Try On started bare, the Brows tab turned its makeup preview off for a brow that was off, which stopped the makeup
engine and with it the brow guide (drawn by that engine). Now the tab keeps the engine on and only drops the brow picture
(`browOverlay = nil`, natural brow left alone). The face landmarker the engine starts for the blush cheek fit is stopped
whenever the engine has nothing to draw (e.g. the Eyeliner tab), so it no longer runs beside the eyeliner's own MediaPipe
detector. The eyeliner cause is not confirmed on a device.

## Blush tutorial comparison like eyeliner, one camera — -Nimah (2026-10-30)

The Blush tab uses the five compare layouts the way the eyeliner does: look | guide, guide | look, look | plain,
plain | look, plain. The pigment is clipped to the look's half (`EyebrowConfiguration.pigmentHalf`, engine
`Settings.pigmentHalf`: full, left, right, none; scissor in `render`), the animated guide (`BlushTutorialOverlay`) to the
guide's half over the bare camera. The Metal camera stays on in every layout (`showMakeupPreview` true for the tab), so the
halves never come from different cameras: `RealCameraView` (a second ARSCNView, a visible seam) is now used by the Brows
tab only. `comparisonSplit` still means `.left` when `pigmentHalf` is nil. Device check pending.

## Try On starts bare, keeps each tool's choice, shows all together — -Nimah (2026-10-30)

`TryOnHomeModel.enabled` starts empty on every launch (no makeup on any tool). Picking a tool only shows its controls; a
tool goes on when a shade, blush look, brow picture or strength is chosen for it, off with the no-makeup button, and keeps
that state and its last choice across tool switches. All tools that are on show together. `BeautyBlushEngine` can now draw
blush and brow in one frame: `prepareBlush` (fit, atlas, mask, visibility, smoothed mesh, tutorial outlines; before the
encoder) and `encodeBlush` (depth prepass, pigment) are used by the blush-only `render` and by `drawBrow` when
`Settings.withBlush` (between the camera and the brow strip). The brow path runs whenever the brow is on
(`isBrow = needsBrow`, was `needsBrow && !needsBlush`, which dropped the brow whenever blush was on, also in the tutorial
photo). Brow and blush keep separate tint/strength (`blushTint`, `blushIntensity`) and visibility (`blushVisibility`); with
both on, the brow tracker's answers also feed the blush cheek fit (`addBlushSample`). `TryOnHomeModel.tutorialHandoff`
carries `enabled`: each tutorial tab previews its tool as last chosen, and a tab for a tool that was off guides without
a makeup preview (the eyeliner tab still shows its liner). The photo step stays Hanum's plain camera (merged 2026-10-30).
Device check pending.

## Blush skin tone fix, iOS 26.5 target — -Nimah (2026-10-30)

Device feedback over three rounds (darker cheeks, then a hazy camera, then "brighter when Try On is off"). Final state:
the Metal camera (blush and brow) now shows the tone ARSCNView shows. Measured on iPhone 17 from paired screenshots
(Try On on with no pigment / off, same scene): neither the sRGB decode (up to 13/255 too dark in the mid-tones) nor the
BT.709 decode (11/255 too light in the shadows, the haze) matched. A fitted 11-knot curve, `cameraTone` in
BeautyBlush.metal and `BeautyBlushConfiguration.cameraTone` (a test keeps them equal), left under 1.5/255 of systematic
error per brightness band on blocks not used to fit it; `decodeCamera` applies it, then the inverse of the drawable's sRGB
encoding, whatever the transfer tag. One device, one scene, lossy screenshots: re-measure if another iPhone differs. The
blush layer is colour-managed as sRGB. The darker cheeks came from the absorbing layer in `pigmentTarget`; the target is
rescaled to 95% of the skin's own luminance (test: at least 92% of bare luminance). Fixtures that hand-write camera
colours use `BeautyBlushConfiguration.cameraLinear`. `IPHONEOS_DEPLOYMENT_TARGET` 26.6 -> 26.5 so the app installs on
iOS 26.5 phones and runs on this Mac's 26.5 Simulators (Xcode 26.6 here ships the 26.5 SDK); no 26.6 API is used.

## Blush tutorial per UX spec 3.5 — -Nimah (2026-10-29)

`GuidedTutorialModel.blushLessons`: two steps, "Dab a little blush inside the small circle." / "Dab outward to blend it
into your skin.", with their own `blushStep` (the brow model's three blush lessons are no longer used here). Caption is
`stepCaption` (spec 1.1: STEP n OF 2 at 70%, 4 pt gap, `AppColors.captionFill` #370B21, radius 18, 22 x 4 padding, max
300 pt). `BlushTutorialOverlay` draws, anchored to each cheek: step 1 the inner dotted circle (0.38 of the pigment field)
with a fingertip dabbing three times and a pink tap ring; step 2 also the outer dotted line (0.82), the ring between them
pulsing 20%-50% every 2 s, the fingertip dabbing outward along the look's direction. 3 s animation, 2 s rest, repeat;
Reduce Motion shows the last frame and a still 40% ring; thermal `.serious` pauses the loop. Outlines are bound to the
mesh at bake (`BeautyBlushEngine.guideOutline`), projected with the pigment's own filtered vertices and `mvp`
(`projectGuide`) at 30 Hz, and published through `FaceCameraState.blushGuide` (`BlushGuideFeed`). The blush shader
contour is off (`tracking.y = 0`); Try On never used it. Camera messages (spec 1-2) are not implemented. Device check pending.

## Blush cheek fit from MediaPipe landmarks, wide natural wash — -Nimah (2026-10-29)

Device feedback: blush too small and not shaped to the face. For Youthful/Sunkissed/Lifted, `BeautyBlushEngine` now runs
the shared MediaPipe tracker while blush is selected, only until the cheek fit is measured: 17 landmarks per frame
(`BlushCheekLandmarks.pairs`: eye corners, lower lid, nostril wing, mouth corner, cheekbone, apple, face edge) are lifted
onto the same frame's ARKit mesh (`BrowFaceFrame.faceLocal`), frontal frames only (|yaw|,|pitch| < 15), median of 10,
once per face anchor. `BlushPlacementGenerator.landmarkField` places each cheek in that person's corridor (nostril wing
to face edge, mouth corner to lower lid) with new preset fields `landmark_*` (fractions of the corridor) and a
flat-topped `wash` profile (1 - smoothstep(r), atlas `paint.z`), cut softly by nose/lid/face-edge feathers. Pigment is
still drawn on the ARKit mesh with ARKit UVs. Until the fit arrives, or when it is implausible, the ARKit-only fit is
drawn (one re-bake when it arrives, no crossfade). Look `max_alpha` 0.48 -> 0.34. Other blush styles are unchanged.
Synthetic tests only; device look pending.

## Skin-preserving blush compositing and blush lab — -Nimah (2026-10-29)

Blush stays a UV atlas on the native ARKit mesh; placement/silhouettes are unchanged. Fixed in
`BeautyBlush.metal.txt` (its camera decode stands; see the 2026-10-30 entry above); default blend colours low-frequency skin
(`detail_radius_px`, new required JSON field, 2...16 camera px) and puts back each pixel's luminance ratio and chroma
residual, keeping pores, highlights and freckles; out-of-gamut colours move towards their own luminance instead of
per-channel clamping; tutorial contour is an antialiased isoline. Alpha 0 is exactly the camera pixel.
Developer tools + Blush: `BlushDebugMenu` picks blend (pigment, previous, linear alpha, multiply, soft light) and
diagnostics (neutral, UV checker, mask, boundaries, visibility, wireframe). No MediaPipe blush renderer, Banuba or
BytePlus exists; the orphan `Features/Blush/Comparison/` files are not in the project. See ADR 0017 and
`Docs/blush-rendering.schema.json`. Synthetic Simulator tests only; device look pending.

## Tutorial camera handoff and welcome revision — 2026-10-29

Try On deactivates before pushing tutorial. Paused/revoked/dismantled ARSCNViews detach
from the shared ARSession; resume reattaches before acquiring the delegate. This avoids
retained navigation views remaining attached while the new screen owns the camera.
Tutorial split comparison uses the same Metal camera pass, with pigment scissored to
the left half, instead of attaching a second ARSCNView to the shared session. Tutorial
handoff carries brow overlay/hiding settings; Filter Off also disables natural-brow hiding.
Welcome version 2 migrates devices that already dismissed revision 1, without resetting
saved data. Verified device preference was revision 1 before install.

381 Simulator tests executed, 4 skipped, 0 failures, including lease/detachment,
tutorial configuration and welcome migration regressions. Signed Release build and
installation on Nimah New succeeded. Physical tutorial camera/compare acceptance pending.
Logs: /tmp/sunrise-tutorial-camera-tests.log and /tmp/sunrise-tutorial-camera-release.log.
Existing local Xcode project/signing and strings edits preserved. No push or main change.

## Staging integration merge — 2026-10-28

Merged integration blush v0.5, mask continuity and hi-fi welcome with staging's latest
MediaPipe/ARKit-pose brow, overlays and MI-GAN work. Staging's scan-free home remains:
the versioned welcome dismisses directly to Try On; historical scan/Profile migration
notes below describe the integration parent, not this merged flow. Brow tracking,
overlay selection, erasing and 3D rendering remain from staging. Blush retains its
native UV pipeline, three looks, palette and tutorial handoff. Device QA is pending.
## Brow frame rate — Khalish (2026-10-29)

No frame cap until the phone is hot: `BrowLoad.trackerFPS`/`drawFPS` are nil at nominal and fair thermal state, so every
camera frame is drawn unless the previous one is still queued, and MediaPipe takes every frame it is free for (`isBusy`).
Serious and critical: 15 fps tracker / 30 fps draw. Lifting landmarks onto the face mesh (`BrowFaceStabilizer`) passes
`projectedVertices()` so each ray tests only triangles around its pixel; `browStrip` evaluates the centerline once per
column (`BrowGeometry.section`). Device check pending.

## Tutorial bottom bar and screen light — Khalish (2026-10-29)

The tutorial's background is `AppColors.wine`, like Try On. Its bottom bar is compare (`CameraBarButton`, left), the tabs
Blush / Brows / Eyeliner, and the screen light (right). `ScreenLight` (DesignSystem/Components) sets brightness to 1 and
`ScreenLightGlow` draws a 24 pt `AppColors.ringLight` (#FFF4EA) frame round the camera; leaving restores the brightness,
backgrounding suspends it and returning turns it back on. Try On has no light
button yet. Simulator build only; device look pending.

## Brow drawn on every ARKit frame — Khalish (2026-10-29)

Like blush, the brow now draws each ARKit camera frame (`drawLiveBrow`, up to `BrowLoad.trackerFPS`, skipping frames while one
is still queued) instead of only when MediaPipe answers. A MediaPipe answer only updates `browLatest` (steadied on that frame's
face by `BrowFaceStabilizer`); each live frame moves it onto its own face pose (`BrowFaceStabilizer.reproject`), or draws it
where it was seen when ARKit had no face, and drops it after 0.5 s without a new answer. The camera picture no longer waits for
MediaPipe. Device check pending.

## Brow code split out of BeautyBlush — Khalish (2026-10-29)

There is still one makeup engine, `BeautyBlushEngine` (blush and brow share its camera session, Metal layer, hand mask and
shader library). Its brow-only parts now live in `Features/Brow/Engine/` as extensions: `BrowEngine+Tracking` (fps cap,
`BrowLoad`, handing frames to MediaPipe), `BrowEngine+Draw` (brow strip, texture/picture, `drawBrow`), `BrowEngine+Hair`
(3D hair), `BrowEngine+Marks` (tutorial mapping, tracking view), `BrowEngine+Fixtures` (DEBUG test helpers), plus
`BrowEraser`/`BrowInpainter` and the brow shaders `Brow.metal.txt`. `BeautyBlushEngine.swift` keeps stored state, setup,
configure/pause/submit, camera decoding, the mask and blush. Engine members are internal (not private) so the extensions
in other files can reach them. `BeautyBlushShaders.sources` joins `BeautyBlush.metal.txt` then `Brow.metal.txt` into one
library (brow shaders use the shared helpers defined first); shader changes are only checked at runtime, by the tests.
No behaviour change.

## Brow load: SceneKit, fill model, temperature — Khalish (2026-10-29)

The `ARSCNView` under the brow's Metal layer stays at 60 fps: slowing it to 10 (tried 2026-10-29) also slowed the ARKit
frames the brow is drawn from, and the brow lagged and dropped out. MI-GAN (`BrowEraser.modelDue`) is asked again only after the face crop moved more than 6% of its size or
1 s passed (never sooner than 0.12 s); its answer stays mapped in brow space between requests. `BeautyBlushEngine.BrowLoad`
follows `ProcessInfo.thermalState`: nominal 40 fps tracker / 15 Hz mask / model; fair 30 fps / 10 Hz / model ≥0.5 s;
serious and critical 20 fps / 8 Hz / no model (push-pull fill only). Not measured on a device.

## Tutorial follows the Try On brow filter — Khalish (2026-10-29)

`TutorialHandoff` now carries `browOverlay` and `hideNaturalBrow` besides tool, shades and intensities; the Brows tab draws that
picture with the chosen shade and strength (`GuidedTutorialModel.liveConfiguration`). The tutorial no longer shows the landmark
view: brow mapping as with a pencil: dashed magenta lines from each side's nostril wing (MediaPipe 129/358, as an offset
from the steadied ala 98/327) through the inner eye corner (Start), the iris ring's outer edge (Arch; 469-472/474-477, else
iris centre + 0.2 eye width) and the outer eye corner (End), with cyan dots and labels where they cross the brow
(`BeautyBlushEngine.mappingMarks`, full-filter mode only). The mapping is drawn as soft white dashes with small pink
dots ringed in white, no labels. The Brows tab has its own five steps (`GuidedTutorialModel.browLessons`: brush up, mark three
dots, outline, fill, brush through; its own `browStep`, not the brow model's step) shown as a spaced "STEP 1 OF 5" over one
instruction in a wine pill; the mapping shows only on the dot and outline steps (`browMappingSteps`). The guide and the brow no longer wait for
the face-skin mask: a mask up to 0.6 s old keeps hands in front, an older one draws the brow without occlusion instead of
fading it out (the brow used to vanish whenever the segmenter fell behind). Brow tracking runs at up to 40 fps (`browMaxFramesPerSecond`, one frame per 1/40 s slot: two of every
three 60 Hz camera frames), still skipped while MediaPipe is busy. Try On → tutorial no longer hangs: `LiveGuideView` keeps a screen whose camera
lease was taken (`revoked`) from taking it back until it is paused. The split
button's "real" half was a second `ARSCNView` (`RealCameraView`, removed 2026-11-01: the engine scissors the look instead). Simulator tests only; split and smoothness need a device check.

## ARKit pose for the brow, and the 3D hair brow — Khalish (2026-10-28)

Details in `Docs/Decisions/0015-arkit-brow-pose.md`. `BrowFaceStabilizer` lifts MediaPipe's brow landmarks onto ARKit's face
mesh (same frame's anchor), smooths them in face-local metres and projects them back (fallback: the image-space smoother when
ARKit has no face or disagrees). "Brow 3D" (`BrowOverlay.is3D`) draws `brow-hair-3d.obj` ribbons on ARKit's pose with a depth-only
face mesh pass, 1.5 px minimum hair width, ambient-light shading and the hand mask; it falls back to its picture without a tracked
face. Removed from the picker list (`BrowOverlay.all`) on 2026-10-29, with Brow 3 (its image set `brow-overlay-3` stays in the assets, unused); the 3D renderer stays, add an `is3D: true` entry
to bring it back. New shader code is only checked at runtime: compile the shader sources (`BeautyBlushShaders.sources`) with `MTLDevice.makeLibrary(source:)` (a build
does not) and run the tests, which fail every engine test if it does not compile. Device check pending.

## Brow overlay pictures — Khalish (2026-10-28)

The eyebrow tool draws a chosen PNG brow (`BrowOverlay.all`, image sets `brow-overlay-N` in `Assets.xcassets`, head left,
tail right, alpha) over the hidden natural brow. `BrowOverlayPicker` lists them horizontally under the tool strip, after a "no overlay" tile (`browOverlay == nil`: no picture, natural-brow hiding unchanged). Try On
now starts with "Landmarks" off and "Natural brow" off (hidden); both toggles stay as test switches. `BrowSpriteBaker` bakes
a picture off the render queue into the existing brow-space texture (u 0...1 = its head-to-tail span, one picture width =
one brow width, drawn in chord space: `BrowGeometry.chordOffset` adds the user's own brow rise when the strip samples it, so the
picture keeps its own arch; strands stay visible through the shade via the texture's alpha channel = relative luminance).
`EyebrowConfiguration.browOverlay` (nil in the tutorial, which still shows tracking only) turns on the shape pass
(`browPigment` is gone; it follows the overlay). Initial eyebrow intensity is 0.9. To add a brow: add an image set and a
`BrowOverlay` entry. The older `BrowStylePicker`/`BrowDesign` shapes stay, unused while `showsBrowTracking` is on.
Simulator tests only; device look pending.

## Black screen background — Khalish (2026-10-28)

`AppColors.screen` (black) is the full-screen background of the tutorial, the palette sheet and placeholder pages;
`AppColors.wine` stays for pills and accents. Try On's background is `AppColors.wine` (#660033) again (2026-10-29).

## Brow tracking view — Khalish (2026-10-27)

`EyebrowConfiguration.showsBrowTracking` (currently `true`) hides the brow shapes and the shape picker; the eyebrow
tool and the tutorial Brows tab show MediaPipe's tracking instead. The Metal engine draws, on the same frame as the
landmarks: all 478 face points (dim white), raw brow points before smoothing (grey), smoothed upper (red) and lower
(orange) brow contours, the fitted centerline (yellow), the brow frame where a shape would be drawn (cyan, green ticks
at head/middle/tail) and eye corners, iris, alae and nose bridge. `BrowTrackingOverlayView` labels each point with
its MediaPipe index and shows yaw/pitch/roll, landmark latency and rate (English-only developer view, fed by
`FaceCameraState.browTracking`). Set the flag to `false` to bring the shapes and picker back. Device check pending.
Test toggles under the eyebrow tool (`TryOnHomeModel.browLandmarksVisible` / `naturalBrowVisible`): "Landmarks"
shows/hides the whole tracking overlay (points, contours, lines, labels, readout). "Natural brow" off hides the user's
own eyebrow (`EyebrowConfiguration.hideNaturalBrow`) through `BrowEraser` (ADR 0014): each brow is unwrapped into a
brow-space texture array (`browUnwrapFragment`), a blurred skin estimate is pulled from mip level 4 up, pixels around
the brow clearly darker than it are the real brow edge (`browHairFragment`, beyond MediaPipe's rows, never past the
eyelid bound) and join the hide mask, then the brow is filled by push-pull without them, given full-resolution
forehead texture (`browFillFragment`, always on), blended frame to frame, and laid back by the brow strip. `BrowInpainter` adds MI-GAN (Core ML, bundled `Resources/MIGANFace256.mlpackage`, MIT, notice in
`Resources/MI-GAN-LICENSE.txt`, reproduce with `Tools/MIGAN/convert_migan_coreml.py`) on an upright face crop every
0.12 s, cached in brow space and faded over the push-pull fill. Area: `concealUpper` /
`concealLower` (lower end ≤85% of the way to the eyelid row `BrowEyeMarks.lid`), long head/tail fades. Hands stay in
front (face-skin mask). This is the only place the
natural brow is erased, and only while that toggle is off; it is a test, not checked on a device. The readout's yaw/pitch/roll are turned to
the screen (`BeautyBlushEngine.screenPose`): MediaPipe's matrix follows the sensor, which read roll near -90° in portrait.

## New brow shape list — Khalish (2026-10-27)

The old eight brow presets (natural, soft/high/low arch, angular, rounded, straight, lifted) and the thin/feathered
modifiers are gone. `EyebrowStyle` is now nine shapes in picker order, following the user's TikTok effect screenshot
(shape categories only, no assets copied): boldArch, slimArch, softNatural, flatStraight, curvedArch, peakedAngle,
slimStraight, fullArch, boldStraight, each a `brow.*` preset in makeup-reference.database.json (source `brow_D`).
Default/oval look is softNatural. Face-shape assignments map to the nearest new shape (round bold arch, square curved
arch, oblong flat straight, heart slim straight, diamond slim arch). Picker thumbnails draw the real `BrowDesign`.
Parameters are engineering proposals; device look acceptance pending.

## Eyebrow on MediaPipe — Khalish (2026-10-27)

The eyebrow try-on/tutorial no longer uses the ARKit mesh or Vision. `MediaPipeBrowTracker` (Face Landmarker, live
stream, transformation matrix on) runs on the shared ARKit camera frames; `BeautyBlushEngine` draws each frame with
its own landmarks (`submitBrow`/`renderBrow`). `BrowObservation` holds brow contours, eye/nose points and
`BrowHeadPose`; `BrowObservationSmoother` filters them; `BrowGeometry` lays a brow-local strip over each brow;
`BrowDesign` turns the style's rule fields into a brow-space curve, baked into a mipmapped texture. Overlay only, same
face-skin occlusion. Original brow pixels are segmented in the shader ("Original brow mask" debug view), not erased.
Tutorial guide outline and nose-eye mapping lines are drawn in Metal; the SceneKit brow guide is only the fallback.
Blush is unchanged (ARKit mesh + Vision fit). `MediaPipeBrowTracker.swift` is a fourth file importing MediaPipe.
See `Docs/Decisions/0013-mediapipe-eyebrow.md`. Simulator tests only; device QA pending. Sections below that
describe the brow on the ARKit mesh, `BeautyBrowStabilizer` or the brow UV atlas predate this.

## Eyebrow switching and tutorial comparison — 2026-10-27

Style changes retain the last committed brow atlas while the new native UV bake is prepared. Failed bind attempts are throttled, while a new requested style resets that throttle and is attempted on the next frame. In the tutorial Brows split comparison, hide placement and mapping outlines so the filtered half compares pigment with the real brow cleanly; the full-filter tutorial still exposes its guide.

## Brow overlay only, anti-blink, debug views — Khalish (2026-10-27)

Per `eyebrow_filter_rendering_fix.md` (Option B): the brow is an overlay, the natural brow is NOT erased. The earlier erase/inpaint
(vertical skin bridge) made horizontal bands and a soft rectangular patch over the brow area and was removed. Composite is straight
alpha, `result = mix(camera, hair, browAlpha)`; browAlpha is zero outside the baked brow, so other pixels are the camera pixel
(fixture test checks this). Strand density floor .35 so skin shows between strands. Each brow is fitted per side from its own
Vision points (`EyebrowGuideGenerator`); camera/mesh mirroring is the existing paired displayTransform/projection.
Anti-blink: brow keeps the last face-skin mask for up to `browMaskGraceSeconds` (0.3 s) instead of dropping out at 150 ms;
brow pixels count as occluded only when skin 9 mm above or below is too (the segmenter often rejects brow hair). Blush unchanged.
Debug: with developer tools on (long-press the logo) and eyebrow selected, a ladybug menu on the camera card picks
`BrowDebugView` (`beautyBrow.debugView`): final, original, landmarks (brow points + eye centers), fit contours (design edge cyan,
observed centerline yellow), alpha mask (white on black), texture only (on grey). English-only, like Scan Debug. Device QA pending.

## Brow style picker — Khalish (2026-10-27)

With the eyebrow tool selected, `TryOnHomeView` shows `BrowStylePicker`: all 8 database brow styles (`EyebrowViewModel.browStyleChoices`,
database order) in one horizontal row under the tool strip. `chooseBrowStyle` sets `configuration.style`, which the live pipeline already
re-fits and re-bakes. Default stays natural. Not carried into the tutorial handoff. Checked on Simulator UI only; live render needs a device.

## Face/eye scan removed from the flow — Khalish (2026-10-27)

The app opens straight on `TryOnHomeView`: no welcome, onboarding, face scan, eye scan, Profile, Retake or
Scan Debug tab. Routes `faceScan`, `eyeScan`, `fullScan`, `profile`, `scanDebug` and `AppTab.scanDebug` are gone,
as are `AppNavigator` onboarding/launch-scan/retake state. No face or eye shape is shown anywhere. Everyone gets
`FaceShapeAssessment.standardLook` (oval assignment: natural brow, cheekbone blush) and the natural eyeliner.
Brow/blush attachments are fitted from live try-on/tutorial frames (`LaunchMakeupFit.fitLive`, one Vision
attempt at most every 0.4 s, frontal and relaxed face) and then followed by ARKit; `LaunchMakeupFit.shared` is
memory-only, cleared on each camera session start, and deletes the old `savedMakeupAttachments.v1` key.
FaceShape/EyeShape/Onboarding/ProfileView/ScanDebug code stays in the repo, unreferenced, so it can return.
Sections below that describe the launch scan, saved fit or Profile predate this. Not yet checked on a device.

## Mask continuity and welcome migration — -Nimah (2026-10-28)

Device screenshot showed Preparing makeup visibility; scalar report error=none, GPU about1ms, ~60FPS.
Fix actual hard freshness gate: reprojection uses three native head anchors; 150ms fresh window plus bounded
100ms smooth opacity fade (new consumed mask_fade_seconds). Never show after250ms; no unlimited old mask.
Opacity target is continuous and capped by mask weight, not hard fresh ? alpha : 0. Stale/mismatched dimensions
and implausible reprojection remain excluded. Status waits for low effective visibility. This permits brief
stale-mask fading, not perfect new-hand occlusion: validate on device.
Welcome revision gate dandan.welcome.version shows new hi-fi welcome once on upgrade. Get Started dismisses
welcome; users with completed face/eye results go to try-on, fresh users enter face then eyes. No scan erasure.

## Hi-fi welcome onboarding — -Nimah (2026-10-28)

Welcome uses OnboardingWelcomeScreen, static generated onboarding-silk asset and native logo/copy/CTA.
Match supplied burgundy silk reference. Responsive scroll fallback, Dynamic Type-scaled text, light status
appearance and four progress dots (welcome/face/eyes/preparing). Get Started still enters face scan then eyes.
Preserve saved-scan bypass and Retake routing. No fake system status bar or rasterized controls; no animation,
second camera or model added. Existing in-flight blush look changes stay intact. No merge/push requested.

## Three reference blush looks v0.5.0 — -Nimah (2026-10-28)

User requested Youthful / Sunkissed / Lifted options, overriding prior no-style-picker for blush only.
JSON presets drive the three shapes; same per-cheek anatomical fitting. Sunkissed alone adds upper-nose
bridge channel. Curved Lifted mask, continuous soft falloff, mipmapped pigment atlases, capped 0.25 mm blush
mesh residual and blush-only mask-confidence threshold. No retouch/morph/scan/extra tracker. Five new colors
(total nine), design approximations only. Selected look handed to tutorial; shade/intensity stay independent.
See Docs/Decisions/0013-three-reference-blush-looks.md. Do not merge staging/main without new instruction.

## Brow stability — -Nimah (2026-10-27)

User reports eyebrow jitter after availability recovery. Native brow residuals now use metre-space 2 Hz /
80 Hz-per-metre-second One Euro filtering plus 0.12 mm output hold; gaps >150 ms reset. Rigid face/camera pose
remains unsmoothed. Brow-only UV atlas gets mipmaps and anisotropic trilinear sampling to reduce strand
minification shimmer. Blush keeps its prior filter and non-mipmapped atlas. Physical acceptance pending.

## Makeup visibility recovery — -Nimah (2026-10-27)

Device scalar metrics showed segmentation_unavailable: CancellationError() despite segmenter_available=true;
mask age 223 ms exceeded the 150 ms freshness guard. Native beauty engine now owns/cancels preparation task,
ignores expected navigation cancellation, clears recovered segmentation/fitting errors and resets status on
pause. Opt-in faceSkinOnly preprocessing uses 256 long side for the bundled 256 model; Hanum default stays512.
Do not remove stale-mask occlusion protection or claim all visibility delays are fixed without device checks.

## Personal blush v0.4.0 — -Nimah (2026-10-27)

Face shape picks artistic style; per-side cheek corridor and observed mouth/nose-to-eye spacing adapt
center and radii. Uses stored native geometry, independent sides, explicit bounded JSON controls and
conservative exclusions; no second scan/tracker or semantic cheekbone claim. Shared native mouth-boundary
helper now lives in BlushPlacementGenerator. Keep Metal and tutorial using the same fields. Preserve all
pending eyebrow edits and existing eyeliner. See Docs/Decisions/0012-personal-cheek-placement.md.

## Native UV strand eyebrow — -Nimah (2026-10-27)

Eyebrow After uses the shared BeautyBlushEngine ARKit/Metal pipeline, one selected category at a time.
A native UV atlas bakes 80 measured/JSON-shaped centerline segments (40 per side); procedural stable strands,
head fade, taper, feather and max alpha. Brow fragment uses separate hair pigment shading, not blush tint.
Preserve observed head/tail, existing face-shape assignments and saved scan flow. No extra scan or tracker.
Category mode is part of atlas cache identity; hide old layer and epoch-guard GPU completions on switching.
SceneKit pigment disabled when Metal owns that category; guides/fallback retained. Metrics beautyBrow.metrics.
Natural hair is not erased: a lighter shade cannot bleach dark brows. Face-skin segmenter is shared, not a
specialized eyebrow/hair matting model. Physical device quality and segmentation need acceptance.

## Blush camera parity — -Nimah (2026-10-27)

Removed the extra horizontal reflection from both Metal camera sampling and mesh projection.
Blush now uses ARFrame displayTransform/projection directly to match the existing ARSCNView categories.
Keep camera and mesh transforms paired; do not introduce category-specific mirroring. Device acceptance pending.

## Native UV Metal blush — -Nimah (2026-10-27)

Primary blush engine is ARKit + Metal via BeautyBlushARView/BeautyBlushEngine, sharing the existing ARSession.
Shader source runtime-compiles once off-main from BeautyBlush.metal.txt. Author mask: blush-wash-mask.png;
separate validated render/tracking configuration: blush-rendering.json. Native UV atlas, native mesh depth
prepass, synchronized camera/pose, linear matte absorption/tint, local One Euro residual smoothing, pose/stretch
gating, and face-skin-only visibility from the existing MediaPipe multiclass segmenter. No second face tracker.
The old CPU grid remains only if Metal setup is unavailable (surfaced status); it is not the active blush path.
Camera/frame/mesh remain transient. Local metrics are scalar timing/state only. Screen pose is not double-smoothed.
Legacy Hanum segmenter default remains body-skin; faceSkinOnly is opt-in for blush. No paid SDK is installed.
See Docs/Decisions/0010-metal-blush.md for verified SDK comparison, dependencies and known occlusion limits.
Do not claim TikTok equivalence, 60 FPS, thin-brush occlusion or sustained performance without device evidence.

## Blush v0.2.1 device-feedback calibration — -Nimah (2026-10-27)

User confirmed v0.2.0 visible but requested wider/softer. Six active radii expand to 0.185–0.225 W by
0.120–0.135 W. Numeric upper range extended explicitly for major radius (0.24 W); no hidden multiplier.
JSON falloff_smoothstep_mix=1 smooths radial alpha; independent inward-safe mask transitions use 0.022 W.
Blush sampling grid increases to 48x32, cached on placement change. User shade/intensity and existing
brow/eyeliner settings remain unchanged. No extra try-on scan. Device acceptance of this revision pending.

## Blush JSON v0.2.0 integration — -Nimah (2026-10-27)

User preference: implement requested JSON revisions into the consuming app in the same task, including renderer
support, checks and build; do not leave an external JSON file disconnected. No automatic staging/main merge.
Bundled full database now merges the six wide-wash blush presets by stable ID. Preserve eyebrow v0.1.1 and all
Hanum eyeliner/scan/profile rules. Blush has wider radii, radial exponent 1.10–1.15, max alpha 0.44–0.48,
default intensity 0.72. Inward smooth mask feather is 0.012 of full face width, decoded and used in coverage.
One field per cheek; do not shrink its radii or use tutorial shapes as pigment. Existing skin bindings and
color-only update caching remain. Saved analysis is reused with no compulsory Retake. The visual target is
art-directed, not pixel-exact or device calibrated; existing lower-lid/hand/hair adapter limits remain.

## Brow size calibration v0.1.1 — -Nimah

Following user feedback, integration JSON increases brow design half-thickness from 3.5% to 6.5% of observed
brow width. Preserve measured head/tail and bounded arch adjustment; no guessed extension. This is an explicit
calibration revision to the bundled copy; the original research artifact remains unchanged. Device visual
acceptance pending. Hand/hair occlusion masking for brow/blush is still not implemented.

## Pigment depth compositing — -Nimah

FaceRegionPreviewRenderer cosmetic materials composite over camera video without reading the coarse native
face depth buffer. Their placement still uses measured front-skin barycentric attachments, not screen offsets.
Guide/eyeliner depth policies remain unchanged. Render tests must include a colorless depth-writing occluder;
a blank SceneKit scene cannot detect self-occlusion. Device visual confirmation is still required.

## JSON makeup integration — -Nimah (2026-10-26)

Integration previews consume bundled `Resources/makeup-reference.database.json` through `MakeupRuleDatabase`.
JSON assignments supersede historical A defaults: oval natural/cheekbone; round high arch/high cheekbone;
square rounded/apple; oblong straight/horizontal; heart low arch/center cheek; diamond soft arch/temple.
Uncovered rectangle/pear stay unavailable. Research draft is explicitly enabled for integration calibration only.
Brow local displacement, two cubic segments, taper, head fade, feather and pigment alpha use rule parameters.
Blush uses full face width, measured per-side eye centers and exact rotated elliptical alpha fields, without
bbox enlargement or tutorial V/dot silhouettes. Palette and initial strength use JSON; custom sampling remains.
No classification or Hanum eyeliner formulas change. No extra try-on scan. Existing saved fit remains usable.
Current adapter uses native ARKit face-local axes and conservative eye-center exclusion where eyelid contours
are absent. Hair/hand occlusion and measured lower-lid masks are not implemented for brow/blush; no production
calibration, product color accuracy or TikTok-equivalent quality is claimed. Device visual acceptance pending.

# AGENTS.md — read this first

## Camera guidance — shared by every tool

`Features/CameraGuidance/` holds what Try On and the tutorial share, for brows, blush and eyeliner alike: `CameraAdvisor(context:)` publishes
the one `CameraMessage` to show (priority, delays and hysteresis live in `CameraMessageEngine`, thresholds in `CameraMessageEngine.Limits`);
`CameraGuidanceCaption` draws it (or a tutorial step) as the spec's caption pill; `ScreenLight` + `ScreenLightGlow` + `ScreenLightButton`
are the screen light. Screens start/stop the advisor and suspend/resume the light with their own lifecycle. The advisor reads
`ARSession.currentFrame` only. While `advisor.message != nil` the preview/guide dims and `advisor.pausesAnimation` holds the step
animation; `reducesLoad` and `pausesSession` follow the thermal state. Eyeliner steps: `LinerTutorialStep` and `LinerStepGuide`
(`Features/Tutorial`). Spec thresholds are untuned guesses; not yet checked on a real device.

## Saved scan flow — -Nimah (supersedes launch-only scan)

Completed face/eye analysis is reused on reopening. Root requires both saved results; Retake in Profile reruns
complete preparation. Sparse barycentric brow attachments and anatomical mapping points persist locally in
UserDefaults (versioned), with vertex/triangle counts and observed confidence. No full mesh, topology array or
camera frame is persisted by fitting. A new live mesh reattaches those sparse descriptors without Vision scanning.
Old installs with analysis but no sparse fit can enter home and explicitly use Profile Retake; unavailable tools
show a message instead of silently rendering nothing. First-launch incomplete analysis still opens onboarding.
Team sources: Khalish scan-overlay-lines b2d8ae0; Hanum Eyeliner-Hanum 071d2a0; profile-page supplies Profile.


## Soft cheek preview — -Nimah

Blush uses a common eye/nose reference for both cheek guides in face-local coordinates. Tutorial dots/V shapes
remain guidance; try-on combines each cheek into a wider elliptical pigment patch with continuous radial alpha.
Observed brow contours are retained even when optional formula annotations cannot bind. No extra try-on scan.
Device visual acceptance is required; these parameters do not establish TikTok-equivalent rendering quality.

## Detector lifecycle — -Nimah

A nil eyeliner style hides output and skips inference while retaining this screen's warmed models.
Only screen deactivation stops/releases them. A category change during startup must not leave startupTask stuck.
Home/tutorial sync is gated by active visibility so hidden routes cannot restart detection.

## Latest integration — -Nimah

Hanum profile `502e423`, eyeliner/tutorial `071d2a0`, and Khalish scan overlays/debug `99791b3` are integrated.
Home retains one selected makeup category, remembered shades/intensities, and launch-only fitting.
Profile retake uses the same complete launch preparation flow; Scan Debug is reachable from the profile toolbar.
Scan landmarks keep the `EyeScanLandmarks` name to avoid colliding with Hanum live `EyeLandmarks`.
Upper-inner blush try-on fills a wider soft cheek area; the tutorial V remains a placement guide.
These notes supersede older all-layers-on descriptions. Device visual/performance acceptance remains pending.


## Tutorial — scan-assigned

`AppRoute.recommendedTutorial(TutorialHandoff)` opens `Features/Tutorial/GuidedTutorialView` (tabs Brows / Eyeliner / Blush, no settings;
shade and strength are carried over from Try On). Eyeliner has three steps (`LinerTutorialStep`) for every look; the look only moves the dots. Not yet checked on a real device.

## Photo — after the tutorial

The tutorial's last-step button enters `GuidedTutorialModel.photoMode` (same screen and camera): full look, coloured frame
(`PhotoTheme`: palette button cycles pink/blue/white), shutter, then `PolaroidResultView`. Views in `Features/Tutorial/PhotoCaptureViews.swift`.
In-memory only; sharing is the only way it leaves the app. Not yet checked on a real device.

## Profile — scan stills

`AppRoute.profile` opens `ProfileView` (face + eye analysis, signature look). Its retake button opens `AppRoute.fullScan`
(`FullScanFlow`: face scan then eye scan in one flow). Portraits are the stills saved by `ScanSnapshots` at scan completion
(face: ARKit frame, oriented via the Vision orientation; eyes: MediaPipe frame cropped around the eyes). Not yet checked on a real device.

## Current merged scope — -Nimah

Smooth try-on — -Nimah: replayed identical scan outputs are ignored before any published state changes.
Brow/blush shade changes update material tint only: keep surface attachments, feather sources and topology.
`FaceRegionPreviewRenderer` uses a 6 mm XY triangle index for exact barycentric binding; live vertex updates
avoid intermediate arrays. Hidden guide renderers return before node construction/animation. Shared-camera
`LinerFrameRelay` budgets overlay delivery to 30 Hz without changing ARKit camera tracking or Hanum formulas.
Non-eyeliner tool/shade/intensity changes do not resynchronize eyeliner. For device performance acceptance,
use a Release build without Xcode's debugger; no measured physical-device FPS is claimed by simulator tests.


Startup recovery — -Nimah: initial face scanning offers tracked frames every 400 ms to a bounded background
`LaunchFitPreparation`; retain the first valid fit, rather than relying on one final frame. Launch fitting can
use observed brow contours without optional pupil/nose formula points; no missing landmarks are invented.
Legacy formula-dependent fitting remains strict. Neutral eyeliner does not block startup. If contour fitting
still fails, retain scan results and offer continuing with available makeup; home explicitly disables and labels
unfitted brow/blush layers instead of claiming they are rendered. Try-on still never runs another Vision scan.


Launch-only scan — -Nimah: `AppNavigator.launchScanComplete` is memory-only and starts false on every cold launch.
Welcome is remembered, analysis is not skipped. Launch runs face scan, eye scan, and transient makeup fitting before
try-on. `FaceAnalysis.scanScreen(onScanFrame:)` exposes the completed AR frame to the launch integrator without
changing classification formulas. `LaunchMakeupFit` keeps only in-memory fitting geometry for the current run;
no image/mesh is written to disk. Try-on/tutorial use `usesLaunchFit` and `followLaunchFit`, which reattach the
initial fit on matching ARKit topology without Vision scanning, sample accumulation or hold-still gates. No scan
prompts or rescan controls appear in try-on. All supported assigned layers start on. Liner live tracking remains
automatic; it skips the legacy Vision fitting phase. Initial preparation failures stay in the launch flow.


Visible pigment fix — -Nimah: layered render snapshots must request `includeBrow: configuration.needsBrow`,
otherwise turning on blush strips the brow input from the renderer. Brow/blush pigment cores use stronger alpha,
14% feather width, 1 mm surface lift, and default intensity 0.85. Before/After and intensity still control visibility.
These are preview rendering parameters, not measured real-world colour accuracy.


Palette try-on — -Nimah: `Features/TryOnHome/PaletteColorPicker.swift` provides a native ColorPicker,
PhotosPicker import and rear-camera capture, followed by tap-to-sample from bounded upright sRGB pixels.
Photos are memory-only and never uploaded/saved. Home dismantles the face camera while picking a palette,
then resumes it; custom RGB only changes shade, not the scan assignment. Presets follow the supplied blush/brow
references approximately (not colour-calibrated product swatches). `AppRoute.recommendedTutorial` carries the
chosen shade/intensity into the assigned Nimah tutorial after the live try-on. Existing camera permission text
includes palette capture; PhotosPicker needs no broad photo-library read permission.


Scan-assigned results — -Nimah: user-facing eyebrow/blush use exactly one stable assigned catalog ID for the saved
face shape (`MakeupPreferenceCatalog.assignedBrow/assignedBlush`); no source/style picker or manual face override.
Uncovered shapes and absent scans leave those layers off. Eyeliner exposes only Hanum's personal eye-scan result,
not the catalog. TryOnHome refreshes saved output changes without rebuilding the camera, and its profile route
opens scan results/rescan actions; the tutorial arrow opens the active assigned category. Data is an on-device
catalog, not a server database. See Docs/BrowBlushPreferences.md for assignments and uncovered shapes.


This section supersedes older status descriptions below. Khalish owns face/eye scanning and saved outputs;
Nimah owns eyebrow/blush placement and tutorials; Hanum owns the eyeliner planner/live overlay. The duplicate
Khalish eyebrow/blush catalog, personalizer and renderer were removed. Shared measurement/data helpers remain.
MediaPipe is used by both eye scanning and eyeliner (including hand occlusion); it is linked only to the app.
The package is pinned to revision `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`.
Khalish's scan-specific landmark model/file is named `EyeScanLandmarks` to avoid Hanum's `EyeLandmarks` collision;
measurement mathematics is unchanged. Both sets of eye tests are retained.
Catalog/import/save and Nimah studio are implemented MVP features, not placeholder-only services.
See `Docs/CodeOwnership.md`, `Docs/Performance.md`, and `Docs/Validation.md`; historical notes below may predate integration.

Home screen: after onboarding the app opens on `Features/TryOnHome/TryOnHomeView` (no tab bar). `TryOnHomeModel` swaps the camera
card between Nimah's blush/eyebrow engine and Hanum's eyeliner engine; profile and tutorial are blank placeholder routes for now.

Saved-analysis flow: onboarding runs Khalish face scan then eye scan. `FaceShapeStore.latest` supplies Nimah
eyebrow/blush presets; `FaceShapeStore.eyes` supplies Hanum eyeliner via the `MakeupPlan` adapter. Saved analysis
opens eyebrow/blush preview directly, with tutorial immediately available. Live geometric alignment is automatic,
not another classification step. Eye-scan measurements are converted using matching units; the lid is never
guessed from `mayBeHooded`. Missing/unclear measurements use the neutral liner. Older scans can still use the
eye measurements embedded in the face result when no separate eye result exists. Eyeshadow is outside this scope.

Eyeliner look (Hanum's overlay): `LinerOverlayRenderer` yields a halo fill plus a body fill per eye; the live canvas and photo
`compose` lay them over the camera picture (normal blending since 2026-11-09), erase a skin-texture grain (`LinerInk`, anchored to the eye) and hand
regions, and tint the pigment with skin sampled from the ARKit frame. Shared tuning constants live in `LinerInk` and `LinerOverlayRenderer`.

Shared brief for anyone working on this repo with an AI coding assistant (Claude Code, Codex, Cursor, Copilot, …).
It covers the project structure, what each feature does and how to use it, and the rules to follow.
`CHANGELOG.md` records what changed. Team docs in `Docs/` are written in Indonesian and give more detail.

**Keep it current:** a change that adds or moves a feature, a public entry point, a route, or a rule updates this
file and adds a `CHANGELOG.md` entry in the same PR.

## Project at a glance

- **SunriseApp** (working name): an iOS app that recommends eyebrow, blush and eyeliner styles for your face shape
  and lets you try them on live with AR.
- SwiftUI, iOS 17+, iPhone portrait. Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY = complete`.
- One third-party dependency: **MediaPipe Tasks Vision** (Swift Package from `google-ai-edge/mediapipe`, pinned to the `v1.1.1` commit `50505c8`; it must be pinned by revision, see ADR 0002), used only by the
  eye scan in `Features/EyeShape`. One app target (`SunriseApp`) and one unit test target (`SunriseAppTests`).
  Why and how: `Docs/Decisions/0002-mediapipe-eye-scan.md`.
- Light MVVM: ViewModels are `@MainActor final class … : ObservableObject` with `@Published`. Stateless views have no ViewModel.
- Apple frameworks, plus MediaPipe for the eye scan: ARKit + SceneKit (face tracking and makeup rendering), Vision (landmarks and face outline), AVFoundation (camera permission and the eye-scan camera), MediaPipe (eye and iris landmarks).

## Build and test

The first build downloads the MediaPipe package (needs internet; Xcode resolves it, no extra tool). Commit `Package.resolved`.

```sh
xcrun simctl list devices available | grep iPhone
xcodebuild test -project SunriseApp.xcodeproj -scheme SunriseApp \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath /tmp/SunriseDerived CODE_SIGNING_ALLOWED=NO
```

- The Simulator has no TrueDepth camera, so the live scan and try-on show their "unavailable" state there. Real AR
  behaviour must be checked on a Face ID iPhone. Say which one you used when you report results.
- `FaceShapeDatasetEvalTests` is skipped unless you pass a labelled dataset:
  `TEST_RUNNER_FACE_SHAPE_DATASET=/path/to/dataset xcodebuild test …` (folders named after shapes, e.g. `Heart/`, `Long/`).
- CI: `.github/workflows/ios-build.yml` builds and runs the unit tests on a macOS 15 runner; Xcode resolves the package.
- MediaPipe gotcha: link the package to the `SunriseApp` target only, never to `SunriseAppTests`. The tests run inside the app, and a second copy of
  MediaPipe crashes at launch ("Function with name ... already registered"). Do not also add it through CocoaPods.

## Project structure

```text
AGENTS.md / CLAUDE.md     AI brief (this file); CLAUDE.md just imports it
CHANGELOG.md              what changed, newest first
Docs/                     team docs in Indonesian: architecture, contracts, scope, testing, ADRs
.github/                  CI workflow, PR and issue templates
SunriseApp.xcodeproj/     explicit PBXGroups: every new file must be added to the project (see Rules)
SunriseApp/
  App/                    SunriseApp entry, AppContainer (composition root), AppRootView (tabs + route destinations)
    Navigation/           AppRoute (all destinations), AppNavigator (tabs, per-tab paths, onboarding flag)
                          Info.plist (camera + photo-library-add usage strings)
  Engine/                 shared engine (Metal, ARKit session, hand mask, MediaPipe tracker) + Camera/, Rules/, Info/, FaceData/
  DesignSystem/
    Theme/                AppColors, AppSpacing, AppTypography (use these, never hard-coded values)
    Components/           GlassKit (frosted glass buttons and pills)
  Features/
    Blush/ Brow/ Eyeliner/ Lips/  one folder per tool: TryOn/ (pickers, looks, config), Engine/ (drawing), Tutorial/ (steps), Info/ (look, kit)
    Screens/              screens that show all tools: TryOn/, Comparison/, Preparation/, Tutorial/, Feedback/
    Onboarding/           Welcome/ (shown once); Splash/, Pages/, CompactOpening/ + EntryFlowView (new flow)
  Resources/              Assets.xcassets (named colours), Localizable.xcstrings
SunriseAppTests/
  Features/               makeup engine, blush, brow, eyeliner, tutorial, camera message tests
  Navigation/             AppNavigatorTests
  TestSupport/            ServiceStubs
```

## Navigation

- The app opens on the welcome (once per `AppNavigator.currentWelcomeVersion`; with `NewFlow` on, the entry screens
  first), then `FeatureHomeView` (a slider of four tool cards, no camera). Routes (`AppRoute`): `tryOn`, `capture`,
  `lookBrief`, `recommendedTutorial`, `feedback` (order in the top section); `AppRootView.destination` builds them. To add a
  screen: add a case, its destination, and push it with `navigator.open(route, in: .tryOn)`; `goBack(in:)`,
  `restartTutorial()` and `returnToRoot(of:)` move back.
- `AppTab` and the per-tab paths in `AppNavigator` remain, though only `.tryOn` is shown.

## Features

Everything the app shows is in `Features/Makeup/` (see the folder note at the top) plus `Features/Onboarding/`
(`OnboardingWelcomeScreen`). The face/eye scan, Scan Debug, the Mac scan editor (`SunriseDebugMac/`), the old try-on and
tutorial, catalog, saved looks and other scaffold pages were deleted on 2026-11-02; sections and notes elsewhere in this
file that describe them are history. Get them back from git history (before commit "chore: delete unused code") if needed.

## Rules

- **Adding files:** create them in `Features/<Feature>/` and add them to the matching group **and** target in
  `project.pbxproj` (PBXFileReference, PBXGroup child, PBXBuildFile, Sources phase). Then build to confirm.
- **Third-party code:** MediaPipe is the only package dependency; the MI-GAN Core ML model (ADR 0014) is the only bundled
  third-party model besides MediaPipe's own, and its MIT notice must stay in `Resources/MI-GAN-LICENSE.txt`. `import MediaPipeTasksVision` is limited to the detector wrappers
  (`MediaPipeEyeLandmarkProvider`, `HandOcclusionSegmenter`, `MediaPipeBrowTracker`); everything else
  works on plain landmark arrays. A new dependency needs an ADR in `Docs/Decisions/`.
- **Dependencies:** inject them through initializers. `AppContainer` is used only in `AppRootView`; features never reach into it.
- **Shared files** (`AppRootView`, `AppRoute`, `AppNavigator`, `AppContainer`, `project.pbxproj`, `Engine/`,
  design tokens, strings): keep edits small and mention them in the PR. Change contracts in their own PR (see `Docs/IntegrationContracts.md`).
- **Concurrency:** strict mode is on. Keep Vision and image work off the main actor (`Task.detached`). Use `Sendable`
  snapshots across actors, and `nonisolated` ARSession delegate methods with `MainActor.assumeIsolated`.
- **UI:** use `AppColors` / `AppSpacing` / `AppTypography` and Dynamic Type text styles. User-facing strings go in
  `Localizable.xcstrings`, with English as the source language.
- **Privacy:** no networking, analytics or uploads. Never persist photos, camera frames or face meshes; the tutorial photo
  stays in memory and leaves the app only through the share sheet. A new permission needs an Info.plist usage string.
- **Honesty:** don't describe mock or sample data as real user results, and don't claim AR works on the strength of a Simulator run.
- **Git:** branch from `main` as `feature/…`, `fix/…` or `chore/…`. Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
  Keep refactors separate from features.

## Out-of-date team docs

These still describe the scaffold from before FaceShape and MakeupTryOn. Trust this file and the code where they disagree.

- `README.md`, `Docs/ProductScope.md`, `Docs/Architecture.md`: say there's no camera or ARKit, two tabs, and onboarding that resets every launch.
- `Docs/NavigationFlow.md`: no Try On tab, `faceScan` or `makeupTryOn` routes.
- `Docs/Testing.md`, `Docs/Validation.md`: the test counts and the "no camera permission" checks are from the scaffold.
- `Docs/IntegrationContracts.md` is current for face shape (section "Analisis bentuk wajah").
