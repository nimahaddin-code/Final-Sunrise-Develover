# Sunrise Scan Editor (Mac)

A separate, Mac-only Xcode project for correcting the face and eye points of scans taken in the iPhone app. It has no camera and
no scanning. It only opens scans exported from the iPhone app and writes the corrections.

## Workflow

1. iPhone app, **Scan Debug** tab: scan, tap **Use this scan**, then **Export for Mac** and AirDrop it to the Mac.
   The file is `face-<name>.sunrisescan` or `eyes-<name>.sunrisescan`: one JSON file holding the scan picture (JPEG), the raw points and the
   corrected points so far.
2. Mac: double-click the file (after the app has been built and run once), drop it on the window, or use **Open…** (⌘O). A folder opens
   every `.sunrisescan` file inside it.
3. Drag the points (or click one and use the arrow keys, Shift for 10 px). Zoom with pinch, ⌘= / ⌘- / ⌘0. ⌘Z undoes.
4. **Final** stage, then **Confirm correction**. Two files are written to the output folder (default `~/Documents/Sunrise Scan Corrections`,
   change it in the sidebar): `<kind>-<name>.raw.json` and `<kind>-<name>.corrected.json`. A name already used gets `-2`.

## Build and run

```sh
xcodebuild build -project SunriseDebugMac.xcodeproj -scheme SunriseDebugMac -destination 'platform=macOS' -derivedDataPath /tmp/SunriseMacDerived
open /tmp/SunriseMacDerived/Build/Products/Debug/Sunrise\ Scan\ Editor.app
```

The built app is named **Sunrise Scan Editor**. Copy it to `~/Applications` so Spotlight finds it. It is unsigned (ad-hoc), not sandboxed, macOS 14+.

## Shared code

The project compiles files from `../SunriseApp` directly (listed in the "Shared with the iPhone app" group): the point models, measuring,
store, view model and export format (`Features/ScanDebug`), the face and eye classifiers and measurers, and `ScanOverlayView`. The
iPhone app's design tokens are replaced by `Stubs/AppColors.swift`. Only files that compile on macOS can be shared: no ARKit, UIKit or
MediaPipe. If you add a dependency to a shared file, add the file it needs to this project too.

The export format lives in `SunriseApp/Features/ScanDebug/ScanDebugExport.swift` (`format: sunrise-scan-debug`, `version: 1`). Both apps
declare the `com.sunrise.scan-debug` type (`.sunrisescan`) in their `Info.plist`.

## Not verified

The app builds and starts with a sample file, but the editor screen has not been checked by eye, and the AirDrop hand-off from a real
iPhone has not been tried.
