import CoreGraphics
import Foundation
import simd

/// Which outline the debug tab is working on.
enum ScanDebugKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case face, eyes

    var id: String { rawValue }
    var title: String { self == .face ? "Face" : "Eyes" }
}

/// The three views of one measurement: what the detector found, what the person moved it to, and the review before saving.
enum ScanDebugStage: String, CaseIterable, Identifiable, Sendable {
    case raw, corrected, final

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// One landmark, normalized to the whole photo: (0, 0) is its top-left corner and (1, 1) its bottom-right.
struct ScanDebugPoint: Codable, Equatable, Identifiable, Sendable {
    /// Stable name such as `cheekbone.left`; "left" and "right" are the photo's sides.
    var id: String
    /// Number shown next to the point.
    var index: Int
    var x: Double
    var y: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// The landmarks of one outline on one photo. It holds numbers only: the photo itself is never kept.
struct ScanDebugPointSet: Codable, Equatable, Sendable {
    var kind: ScanDebugKind
    var imageWidth: Int
    var imageHeight: Int
    var points: [ScanDebugPoint]

    static let faceIDs = ["top", "forehead.left", "forehead.right", "cheekbone.left", "cheekbone.right",
                          "jaw.left", "jaw.right", "chin.left", "chin.right", "bottom"]
    static let eyeParts = ["inner", "outer", "lidTop", "lidBottom", "irisA", "irisB", "brow"]
    static let eyeIDs = ["left", "right"].flatMap { side in eyeParts.map { "eye.\(side).\($0)" } }

    init(kind: ScanDebugKind, imageWidth: Int, imageHeight: Int, positions: [String: CGPoint]) {
        self.kind = kind
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        let ids = kind == .face ? Self.faceIDs : Self.eyeIDs
        points = ids.enumerated().compactMap { index, id in
            positions[id].map { ScanDebugPoint(id: id, index: index, x: Double($0.x), y: Double($0.y)) }
        }
    }

    init(kind: ScanDebugKind, imageWidth: Int, imageHeight: Int, points: [ScanDebugPoint]) {
        self.kind = kind
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.points = points
    }

    func position(_ id: String) -> CGPoint? { points.first { $0.id == id }?.cgPoint }

    /// A point in photo pixels, y down.
    func pixel(_ id: String) -> SIMD2<Float>? {
        position(id).map { SIMD2(Float($0.x) * Float(imageWidth), Float($0.y) * Float(imageHeight)) }
    }

    mutating func move(_ id: String, to position: CGPoint) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        points[index].x = Double(min(max(position.x, 0), 1))
        points[index].y = Double(min(max(position.y, 0), 1))
    }

    /// How far the points sit from `other`'s, in photo pixels, on average.
    func meanShift(from other: ScanDebugPointSet) -> Double {
        let pairs = points.compactMap { point in other.points.first { $0.id == point.id }.map { (point, $0) } }
        guard !pairs.isEmpty else { return 0 }
        let total = pairs.reduce(0.0) { sum, pair in
            let dx = (pair.0.x - pair.1.x) * Double(imageWidth), dy = (pair.0.y - pair.1.y) * Double(imageHeight)
            return sum + (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(pairs.count)
    }

    /// The lines drawn between the points, in the same normalized space.
    var overlay: ScanOverlay {
        func line(_ ids: [String], _ style: ScanOverlay.Stroke.Style, closed: Bool = false, label: String? = nil) -> ScanOverlay.Stroke? {
            let found = ids.compactMap(position)
            return found.count == ids.count ? .init(points: found, style: style, closed: closed, label: label) : nil
        }
        var strokes: [ScanOverlay.Stroke?] = []
        switch kind {
        case .face:
            strokes = [line(["forehead.left", "cheekbone.left", "jaw.left", "chin.left", "bottom",
                             "chin.right", "jaw.right", "cheekbone.right", "forehead.right"], .outline),
                       line(["forehead.left", "forehead.right"], .measure, label: "Forehead"),
                       line(["cheekbone.left", "cheekbone.right"], .measure, label: "Cheekbones"),
                       line(["jaw.left", "jaw.right"], .measure, label: "Jaw"),
                       line(["chin.left", "chin.right"], .measure),
                       line(["top", "bottom"], .measure)]
        case .eyes:
            for side in ["left", "right"] {
                func id(_ part: String) -> String { "eye.\(side).\(part)" }
                strokes += [line([id("outer"), id("lidTop"), id("inner"), id("lidBottom")], .outline, closed: true),
                            line([id("inner"), id("outer")], .measure),
                            line([id("lidTop"), id("lidBottom")], .measure),
                            line([id("irisA"), id("irisB")], .guide),
                            line([id("brow"), id("lidTop")], .guide)]
            }
            strokes.append(line(["eye.left.inner", "eye.right.inner"], .measure, label: "Spacing"))
        }
        return ScanOverlay(strokes: strokes.compactMap { $0 })
    }
}

/// What a set of points measures, plus the classification the app's own classifier gives for it.
struct ScanDebugReport: Equatable, Sendable {
    struct Metric: Equatable, Sendable {
        var key: String
        var label: String
        var value: Double
        var unit: String
    }

    var metrics: [Metric]
    /// "Oval · 62%", or `nil` when the points cannot be classified.
    var classification: String?

    func value(_ key: String) -> Double? { metrics.first { $0.key == key }?.value }
}

enum ScanDebugMeasure {
    static func report(for set: ScanDebugPointSet) -> ScanDebugReport {
        set.kind == .face ? face(set) : eyes(set)
    }

    private static func face(_ set: ScanDebugPointSet) -> ScanDebugReport {
        func width(_ name: String) -> Float? {
            guard let left = set.pixel("\(name).left"), let right = set.pixel("\(name).right") else { return nil }
            return simd_distance(left, right)
        }
        var metrics: [ScanDebugReport.Metric] = []
        func add(_ key: String, _ label: String, _ value: Float?) {
            if let value { metrics.append(.init(key: key, label: label, value: Double(value), unit: "px")) }
        }
        let length = zip2(set.pixel("top"), set.pixel("bottom")).map { simd_distance($0, $1) }
        add("length", "Face length", length)
        add("forehead", "Forehead width", width("forehead"))
        add("cheekbone", "Cheekbone width", width("cheekbone"))
        add("jaw", "Jaw width", width("jaw"))
        add("chin", "Chin width", width("chin"))

        var classification: String?
        if let length, let forehead = width("forehead"), let cheek = width("cheekbone"), cheek > 0,
           let jaw = width("jaw"), jaw > 0, let chin = width("chin") {
            let result = FaceShapeClassifier.photo.classify(
                FaceProportions(length: length / cheek, forehead: forehead / cheek, jaw: jaw / cheek, chin: chin / jaw))
            classification = "\(String(localized: result.shape.title)) · \(Int((result.confidence * 100).rounded()))%"
        }
        return ScanDebugReport(metrics: metrics, classification: classification)
    }

    private static func eyes(_ set: ScanDebugPointSet) -> ScanDebugReport {
        guard let landmarks = landmarks(from: set), let measured = EyeMeasurer.measure(landmarks) else {
            return ScanDebugReport(metrics: [], classification: nil)
        }
        let result = EyeShapeClassifier().classify(measured)
        let metrics: [ScanDebugReport.Metric] = [
            .init(key: "openness", label: "Eye openness", value: Double(measured.openness), unit: "× width"),
            .init(key: "tilt", label: "Eye tilt", value: Double(measured.tilt), unit: "°"),
            .init(key: "spacing", label: "Eye spacing", value: Double(measured.spacing), unit: "× eye"),
            .init(key: "lidSpace", label: "Brow to lid", value: Double(measured.lidSpace), unit: "× iris"),
        ]
        let name = "\(String(localized: result.openness.title)) · \(String(localized: result.tilt.title)) · \(String(localized: result.spacing.title))"
        return ScanDebugReport(metrics: metrics, classification: "\(name) · \(Int((result.confidence * 100).rounded()))%")
    }

    /// The eye points as `EyeLandmarks`, so the same measurer and classifier the scan uses can judge them.
    static func landmarks(from set: ScanDebugPointSet) -> EyeLandmarks? {
        func eye(_ side: String) -> EyeLandmarks.Eye? {
            func p(_ part: String) -> SIMD2<Float>? { set.pixel("eye.\(side).\(part)") }
            guard let inner = p("inner"), let outer = p("outer"), let top = p("lidTop"), let bottom = p("lidBottom"),
                  let irisA = p("irisA"), let irisB = p("irisB"), let brow = p("brow") else { return nil }
            return .init(innerCorner: inner, outerCorner: outer, lid: [top, bottom], iris: [irisA, irisB], brow: [brow])
        }
        guard let first = eye("left"), let second = eye("right") else { return nil }
        return EyeLandmarks(first: first, second: second)
    }

    private static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        if let a, let b { (a, b) } else { nil }
    }
}
