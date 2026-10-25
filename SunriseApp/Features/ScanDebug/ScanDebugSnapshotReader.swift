import CoreGraphics

/// Turns the picture a finished scan produced (`ScanSnapshot`) back into editable points. The face and eye scans already
/// draw their measured landmarks as normalized strokes (`FaceGuide.overlay`, `EyeOverlay.overlay`), so the debug tab reads
/// those instead of measuring again: the raw points are exactly what the scan used.
enum ScanDebugSnapshotReader {
    static func pointSet(from snapshot: ScanSnapshot, kind: ScanDebugKind) -> ScanDebugPointSet? {
        let positions = kind == .face ? facePositions(snapshot.overlay) : eyePositions(snapshot.overlay)
        guard let positions else { return nil }
        return ScanDebugPointSet(kind: kind, imageWidth: snapshot.image.width, imageHeight: snapshot.image.height, positions: positions)
    }

    /// `FaceGuide.overlay` order: the outline (forehead, cheekbones, jaw, chin and tip, down the left and up the right), the
    /// forehead, cheekbone and jaw widths, then the line from the top to the chin tip.
    static func facePositions(_ overlay: ScanOverlay) -> [String: CGPoint]? {
        let strokes = overlay.strokes
        guard strokes.count >= 5, strokes[0].points.count == 9, strokes[1...4].allSatisfy({ $0.points.count == 2 }) else { return nil }
        let outline = strokes[0].points
        return ["forehead.left": outline[0], "cheekbone.left": outline[1], "jaw.left": outline[2], "chin.left": outline[3],
                "bottom": outline[4], "chin.right": outline[5], "jaw.right": outline[6], "cheekbone.right": outline[7],
                "forehead.right": outline[8], "top": strokes[4].points[0]]
    }

    /// `EyeOverlay.overlay` draws each eye as: a closed outline (outer corner, upper lid, inner corner, lower lid), the brow,
    /// the iris ring, the corner line and the opening line; the spacing line comes last.
    static func eyePositions(_ overlay: ScanOverlay) -> [String: CGPoint]? {
        var groups: [[ScanOverlay.Stroke]] = []
        for stroke in overlay.strokes {
            if stroke.style == .outline { groups.append([stroke]) } else if !groups.isEmpty, stroke.label == nil { groups[groups.count - 1].append(stroke) }
        }
        guard groups.count == 2 else { return nil }

        var eyes: [(x: CGFloat, parts: [String: CGPoint])] = []
        for group in groups {
            let outline = group[0].points
            let half = (outline.count - 2) / 2
            guard outline.count >= 6, outline.count.isMultiple(of: 2),
                  let brow = group.first(where: { $0.style == .guide && !$0.closed })?.points, !brow.isEmpty,
                  let iris = group.first(where: { $0.style == .guide && $0.closed })?.points, iris.count >= 2 else { return nil }
            let opening = group.filter { $0.style == .measure }.dropFirst().first?.points
            let ends = opening ?? [outline.min { $0.y < $1.y }!, outline.max { $0.y < $1.y }!]
            let (top, bottom) = ends[0].y <= ends[ends.count - 1].y ? (ends[0], ends[ends.count - 1]) : (ends[ends.count - 1], ends[0])
            // The ring starts at angle 0 and its opposite point is half way round.
            let browCenter = CGPoint(x: brow.map(\.x).reduce(0, +) / CGFloat(brow.count), y: brow.map(\.y).reduce(0, +) / CGFloat(brow.count))
            eyes.append((outline.map(\.x).reduce(0, +) / CGFloat(outline.count),
                         ["inner": outline[1 + half], "outer": outline[0], "lidTop": top, "lidBottom": bottom,
                          "irisA": iris[0], "irisB": iris[iris.count / 2], "brow": browCenter]))
        }
        var positions: [String: CGPoint] = [:]
        for (side, eye) in zip(["left", "right"], eyes.sorted { $0.x < $1.x }) {
            for (part, point) in eye.parts { positions["eye.\(side).\(part)"] = point }
        }
        return positions
    }
}
