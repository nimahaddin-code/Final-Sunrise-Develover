import SwiftUI

/// A scan picture with the measured lines drawn on it. Fits its width and keeps the picture's shape.
struct ScanOverlayView: View {
    let snapshot: ScanSnapshot

    var body: some View {
        Canvas { context, size in
            context.draw(Image(decorative: snapshot.image, scale: 1), in: CGRect(origin: .zero, size: size))
            for stroke in snapshot.overlay.strokes { draw(stroke, in: &context, size: size) }
        }
        .aspectRatio(CGFloat(snapshot.image.width) / CGFloat(snapshot.image.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius / 2))
        .accessibilityElement()
        .accessibilityLabel("Your scan with the measured lines drawn on it")
    }

    private func draw(_ stroke: ScanOverlay.Stroke, in context: inout GraphicsContext, size: CGSize) {
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard points.count >= 2 else { return }
        let path = Self.path(through: points, closed: stroke.closed, smooth: stroke.style != .measure)

        // A dark halo under every line keeps it readable on both light and dark skin and backgrounds.
        var halo = context
        halo.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5))
        switch stroke.style {
        case .outline:
            halo.stroke(path, with: .color(AppColors.rose), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        case .measure:
            halo.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            for end in [points.first, points.last].compactMap({ $0 }) {
                halo.fill(Path(ellipseIn: CGRect(x: end.x - 3.5, y: end.y - 3.5, width: 7, height: 7)), with: .color(.white))
            }
        case .guide:
            halo.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }

        if let label = stroke.label {
            let middle = CGPoint(x: (points.first!.x + points.last!.x) / 2, y: (points.first!.y + points.last!.y) / 2)
            let text = context.resolve(Text(LocalizedStringKey(label)).font(.caption2.weight(.semibold)).foregroundStyle(.white))
            let textSize = text.measure(in: size)
            let box = CGRect(x: middle.x - textSize.width / 2 - 5, y: middle.y - textSize.height - 8,
                             width: textSize.width + 10, height: textSize.height + 2)
            context.fill(Path(roundedRect: box, cornerRadius: box.height / 2), with: .color(.black.opacity(0.55)))
            context.draw(text, at: CGPoint(x: box.midX, y: box.midY))
        }
    }

    /// A straight polyline, or a smooth curve through the same points (Catmull-Rom turned into Béziers).
    static func path(through points: [CGPoint], closed: Bool, smooth: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard smooth, points.count >= 4 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            if closed { path.closeSubpath() }
            return path
        }
        let count = points.count
        func point(_ index: Int) -> CGPoint {
            closed ? points[(index % count + count) % count] : points[min(max(index, 0), count - 1)]
        }
        let segments = closed ? count : count - 1
        for index in 0..<segments {
            let p0 = point(index - 1), p1 = point(index), p2 = point(index + 1), p3 = point(index + 2)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if closed { path.closeSubpath() }
        return path
    }
}
