// -Nimah: shared measuring for the two "line" products, brow and eyeliner: a frame along the target line, and the
// line's outline per column (upper and lower edge, darkness) in that frame. Face-local millimetres throughout.
import Foundation
import simd

/// One sample of a product mask in a line's frame.
struct LineSample {
    /// u along the line (0 = target's inner end, growing outward), v up, mm.
    var local: SIMD2<Double>
    var area: Double
    /// How much darker than skin (or than the bare photo), L* units.
    var dark: Double
    var index: Int
}

/// A frame along a line on one side of the face: u from the inner end outward, v up.
struct LineFrame {
    let origin: SIMD2<Double>, u: SIMD2<Double>, v: SIMD2<Double>

    func local(_ p: SIMD2<Double>) -> SIMD2<Double> { let d = p - origin; return SIMD2(simd_dot(d, u), simd_dot(d, v)) }

    /// The principal axis of the points (area-weighted), u pointing away from the face's midline, origin at the inner end.
    init?(points: [(p: SIMD2<Double>, w: Double)]) {
        let total = points.reduce(0) { $0 + $1.w }
        guard points.count >= 6, total > 0 else { return nil }
        let mean = points.reduce(SIMD2<Double>.zero) { $0 + $1.p * $1.w } / total
        var xx = 0.0, xy = 0.0, yy = 0.0
        for q in points { let d = q.p - mean; xx += d.x * d.x * q.w; xy += d.x * d.y * q.w; yy += d.y * d.y * q.w }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        var axis = SIMD2(cos(angle), sin(angle))
        if axis.x * (mean.x >= 0 ? 1 : -1) < 0 { axis = -axis }
        var up = SIMD2(-axis.y, axis.x)
        if up.y < 0 { up = -up }
        let us = points.map { simd_dot($0.p - mean, axis) }.sorted()
        let inner = us[Int(Double(us.count - 1) * 0.03)]
        origin = mean + axis * inner; u = axis; v = up
    }
}

/// The outline of a mask column by column.
struct LineProfile {
    struct Column { var lower: Double; var upper: Double; var area: Double; var dark: Double }
    let bin: Double
    let columns: [Int: Column]
    let samples: [LineSample]

    init(_ samples: [LineSample], bin: Double) {
        self.bin = bin; self.samples = samples
        var columns: [Int: Column] = [:]
        for s in samples {
            let k = Int((s.local.x / bin).rounded(.down))
            var c = columns[k] ?? Column(lower: .infinity, upper: -.infinity, area: 0, dark: 0)
            c.lower = min(c.lower, s.local.y); c.upper = max(c.upper, s.local.y); c.area += s.area; c.dark += s.dark * s.area
            columns[k] = c
        }
        self.columns = columns
    }

    var area: Double { samples.reduce(0) { $0 + $1.area } }
    var isEmpty: Bool { samples.isEmpty }

    /// u below which `q` of the area lies (robust ends: a stray sample does not move them).
    func quantile(_ q: Double) -> Double? {
        let sorted = samples.sorted { $0.local.x < $1.local.x }
        let total = area
        guard total > 0 else { return nil }
        var running = 0.0
        for s in sorted { running += s.area; if running >= q * total { return s.local.x } }
        return sorted.last?.local.x
    }
    var start: Double? { quantile(0.03) }
    var end: Double? { quantile(0.97) }

    func column(at u: Double) -> Column? { columns[Int((u / bin).rounded(.down))] }

    /// Columns whose u lies in `range`.
    func columns(in range: ClosedRange<Double>) -> [Column] {
        columns.filter { range.contains((Double($0.key) + 0.5) * bin) }.map(\.value)
    }

    func meanCentre(in range: ClosedRange<Double>) -> Double? {
        let c = columns(in: range); guard !c.isEmpty else { return nil }
        return c.reduce(0) { $0 + ($1.lower + $1.upper) / 2 } / Double(c.count)
    }

    func meanUpper(in range: ClosedRange<Double>) -> Double? {
        let c = columns(in: range); guard !c.isEmpty else { return nil }
        return c.reduce(0) { $0 + $1.upper } / Double(c.count)
    }

    /// Mean thickness (upper - lower edge, plus one sample spacing) over `range`.
    func thickness(in range: ClosedRange<Double>, spacing: Double) -> Double? {
        let c = columns(in: range); guard !c.isEmpty else { return nil }
        return c.reduce(0) { $0 + $1.upper - $1.lower + spacing } / Double(c.count)
    }

    /// Area-weighted mean darkness.
    var darkness: Double { let a = area; return a > 0 ? samples.reduce(0) { $0 + $1.dark * $1.area } / a : 0 }

    /// The shape of a brow-like line: ends, the heights there, the highest point and the angles up to it and down from it.
    struct Shape { var start, end, head, tail, archU, archHeight, rise, fall: Double; var length: Double { end - start } }

    func shape() -> Shape? {
        guard let start, let end, end - start > 4 else { return nil }
        let length = end - start, edge = max(0.15 * length, bin)
        guard let head = meanCentre(in: start...(start + edge)), let tail = meanCentre(in: (end - edge)...end),
              let headUpper = meanUpper(in: start...(start + edge)), let tailUpper = meanUpper(in: (end - edge)...end) else { return nil }
        // Highest upper edge between the first 15% and the last 10%, smoothed over three columns.
        let keys = columns.keys.sorted()
        var best: (u: Double, upper: Double)?
        for k in keys {
            let u = (Double(k) + 0.5) * bin
            guard u > start + edge, u < end - 0.1 * length else { continue }
            let near = [k - 1, k, k + 1].compactMap { columns[$0]?.upper }
            let upper = near.reduce(0, +) / Double(near.count)
            if best == nil || upper > best!.upper { best = (u, upper) }
        }
        let arch = best ?? ((start + end) / 2, max(headUpper, tailUpper))
        let chord = headUpper + (tailUpper - headUpper) * (arch.u - start) / length
        let rise = atan2(arch.upper - headUpper, max(arch.u - start, 0.5)) * 180 / .pi
        let fall = atan2(arch.upper - tailUpper, max(end - arch.u, 0.5)) * 180 / .pi
        return Shape(start: start, end: end, head: head, tail: tail, archU: arch.u, archHeight: arch.upper - chord, rise: rise, fall: fall)
    }
}

/// Collects measured rule results (`FeedbackHit`) and score entries for one tool, reading thresholds from the database.
struct FeedbackRecorder {
    let database: FeedbackDatabase
    /// `coordinates.scale`: mm thresholds marked `ipd` grow with the person's own eye distance.
    let scale: Double
    let look: String?
    var hits: [FeedbackHit] = []
    var entries: [FeedbackScoreEntry] = []

    func applies(_ rule: FeedbackDatabase.Rule) -> Bool {
        if let looks = rule.looks, !looks.contains(look ?? "") { return false }
        if let excluded = rule.not_for_looks, let look, excluded.contains(look) { return false }
        return true
    }

    /// Bands `value` with the rule's thresholds and records it. Returns the band (nil when the rule does not apply).
    @discardableResult
    mutating func add(_ id: String, value: Double, side: FeedbackSide, values: [String: String] = [:], size: Double? = nil) -> FeedbackBand? {
        guard let rule = database.rule(id), applies(rule), let t = rule.thresholds else { return nil }
        let band = FeedbackBand.of(value, kind: rule.kind, t, scale: rule.scale == "ipd" ? scale : 1)
        entries.append(FeedbackScoreEntry(band: band, weight: rule.weight, priority: rule.priority))
        hits.append(FeedbackHit(rule: id, band: band, side: side, priority: rule.priority, values: values,
                                size: size ?? abs(value), suppresses: rule.suppresses ?? []))
        return band
    }

    /// A rule that only fires (e.g. "none"), always at its worst band.
    mutating func fire(_ id: String, side: FeedbackSide, band: FeedbackBand = .large, values: [String: String] = [:]) {
        guard let rule = database.rule(id), applies(rule) else { return }
        entries.append(FeedbackScoreEntry(band: band, weight: rule.weight, priority: rule.priority))
        hits.append(FeedbackHit(rule: id, band: band, side: side, priority: rule.priority, values: values, size: 100,
                                suppresses: rule.suppresses ?? []))
    }

    func notOK(_ prefix: String) -> Bool { hits.contains { $0.rule.hasPrefix(prefix) && $0.band != .ok } }

    /// The other side's name for symmetry messages.
    static func pairValues(_ composer: FeedbackComposer, higherIsLeft: Bool, _ values: [String: String]) -> (FeedbackSide, [String: String]) {
        let other: FeedbackSide = higherIsLeft ? .right : .left
        return (higherIsLeft ? .left : .right, values.merging(["other": composer.partName(other)]) { $1 })
    }

    /// Final step: the chosen messages (or praise), and the score.
    func feedback(_ composer: FeedbackComposer, praise: [MakeupFeedback.Item], notes: [MakeupFeedback.Item]) -> MakeupFeedback {
        composer.assemble(hits: hits, entries: entries, praise: praise, notes: notes)
    }
}
