import ActivityKit
import SwiftUI
import WidgetKit

/// The scan's Dynamic Island and Lock Screen presentation: a progress ring while scanning, a green checkmark when done.
/// The extension cannot see the app's asset catalog, so the colours are repeated here (Rose is `Assets.xcassets/Rose`).
struct ScanLiveActivity: Widget {
    private static let rose = Color(red: 0.96, green: 0.60, blue: 0.71)
    private static let done = Color(red: 0.6, green: 0.96, blue: 0.55)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScanActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Ring(state: context.state, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline)
                    Text(context.state.isDone ? "Scan complete" : "Scanning…").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Ring(state: context.state, size: 44).padding(.leading, 4) }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title).font(.headline)
                        Text(context.state.isDone ? "Scan complete" : "Scanning…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isDone {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Self.done).padding(.trailing, 4)
                    } else {
                        Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                            .font(.title3.weight(.semibold)).monospacedDigit().padding(.trailing, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "face.dashed").foregroundStyle(Self.rose)
            } compactTrailing: {
                Ring(state: context.state, size: 20, lineWidth: 3)
            } minimal: {
                Ring(state: context.state, size: 20, lineWidth: 3)
            }
            .keylineTint(Self.rose)
        }
    }

    /// A progress ring that becomes a green checkmark circle when the scan is done.
    private struct Ring: View {
        let state: ScanActivityAttributes.ContentState
        let size: CGFloat
        var lineWidth: CGFloat = 5

        var body: some View {
            if state.isDone {
                Image(systemName: "checkmark.circle").font(.system(size: size, weight: .regular)).foregroundStyle(ScanLiveActivity.done)
            } else {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
                    Circle().trim(from: 0, to: state.progress)
                        .stroke(ScanLiveActivity.rose, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: size, height: size)
            }
        }
    }
}
