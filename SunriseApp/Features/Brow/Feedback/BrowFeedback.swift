// -Nimah: brow feedback. The target is the brow as it looked in the desired-look photo (the chosen picture drawn by the
// engine): every mesh sample clearly darker than the skin there. The result is the same in the result photo; product is
// what got darker than the bare face. Both are compared in a frame along the target brow. Rules and texts:
// `makeup-feedback.database.json` (brow). Not measured yet: head softness, visible outline, colour.
import Foundation
import simd

/// What brow and eyeliner feedback need from the run.
struct LineFeedbackInput: Sendable {
    var before: FaceScan?
    var hadBeforePhoto: Bool
    var after: FaceScan?
    /// Database look id (eyeliner), nil for brows.
    var look: String?
}

enum BrowFeedback {
    /// L* below the skin that counts as brow (hair or product), and the darkening that counts as product (`detection`).
    static let browDark = 12.0, productDark = 4.0

    struct Measured {
        var shape: LineProfile.Shape
        var headY: Double, tailY: Double, thickness: Double, darkness: Double
    }

    static func evaluate(_ input: LineFeedbackInput, database: FeedbackDatabase, language: FeedbackLanguage) -> MakeupFeedback {
        var composer = FeedbackComposer(database: database, language: language)
        composer.part = \.brow
        guard input.hadBeforePhoto else { return BlushFeedback.noBeforePhoto(composer) }
        var check = FeedbackPhotoCheck(before: input.before, after: input.after, tool: "brow", composer: composer)
        guard check.blocking.isEmpty, let before = input.before, let after = input.after,
              before.samples.count == after.samples.count, !before.samples.isEmpty else {
            return MakeupFeedback(score: nil, headline: "", comments: [], items: check.blocking.isEmpty ? check.notes : check.blocking)
        }
        let both = before.samples.indices.filter { before.samples[$0].visible && after.samples[$0].visible }
        let light = FeedbackSkin.shift(before: before, after: after, both: both)
        if light.mismatch { check.report("capture.lighting_mismatch", tool: "brow", composer) }
        guard let skinShown = FeedbackSkin.lightness(before, rendered: true), let skinAfter = FeedbackSkin.lightness(after, rendered: false) else {
            check.report("capture.no_face", ["photo": "Try On"], tool: "brow", composer)
            return MakeupFeedback(score: nil, headline: "", comments: [], items: check.blocking + check.notes)
        }
        let skinNow = Double(skinAfter + light.shift.x)
        func afterL(_ i: Int) -> Double { Double(after.samples[i].lab.x + light.shift.x) }
        func point(_ i: Int) -> SIMD2<Double> { SIMD2(Double(before.samples[i].position.x), Double(before.samples[i].position.y)) }

        var record = FeedbackRecorder(database: database, scale: Double(before.ipd > 40 ? before.ipd / 63 : 1), look: nil)
        let zones = database.words(language).brow_zone
        var measured: [FeedbackSide: Measured] = [:]
        for sign in [1.0, -1.0] {
            let side: FeedbackSide = sign > 0 ? .left : .right
            let area = both.filter {
                let p = before.samples[$0].position
                return Double(p.x) * sign > 8 && abs(p.x) < 75 && p.y > before.eyeY + 3 && p.y < before.eyeY + 45
            }
            let target = area.compactMap { i -> (Int, Double)? in
                guard let shown = before.samples[i].rendered else { return nil }
                let dark = Double(skinShown - shown.x)
                return dark >= browDark ? (i, dark) : nil
            }
            guard let frame = LineFrame(points: target.map { (point($0.0), Double(before.samples[$0.0].area)) }) else { continue }
            let t = LineProfile(target.map { LineSample(local: frame.local(point($0.0)), area: Double(before.samples[$0.0].area), dark: $0.1, index: $0.0) }, bin: 2)
            guard let ts = t.shape() else { continue }
            let lowest = t.columns.values.map(\.lower).min() ?? 0, highest = t.columns.values.map(\.upper).max() ?? 0
            let nearby = area.map { (i: $0, local: frame.local(point($0))) }.filter {
                $0.local.x > ts.start - 12 && $0.local.x < ts.end + 12 && $0.local.y > lowest - 8 && $0.local.y < highest + 8
            }
            let product = Set(nearby.filter { Double(before.samples[$0.i].lab.x) - afterL($0.i) >= productDark }.map(\.i))
            let brow = nearby.filter { skinNow - afterL($0.i) >= browDark }
            let r = LineProfile(brow.map { LineSample(local: $0.local, area: Double(before.samples[$0.i].area), dark: skinNow - afterL($0.i), index: $0.i) }, bin: 2)
            let targetIndices = Set(t.samples.map(\.index))
            let productShare = t.samples.filter { product.contains($0.index) }.reduce(0) { $0 + $1.area } / max(t.area, 1)
            guard productShare >= 0.15, let rs = r.shape() else { record.fire("brow.none", side: side); continue }

            func mm(_ d: Double) -> [String: String] { ["delta": FeedbackComposer.mm(d)] }
            let head = rs.start - ts.start
            record.add(head < 0 ? "brow.head.too_close" : "brow.head.too_far", value: head, side: side, values: mm(head))
            let headV = rs.head - ts.head
            record.add(headV > 0 ? "brow.head.too_high" : "brow.head.too_low", value: headV, side: side, values: mm(headV))
            let tail = rs.end - ts.end
            record.add(tail > 0 ? "brow.tail.too_long" : "brow.tail.too_short", value: tail, side: side, values: mm(tail))
            let tailV = rs.tail - ts.tail
            record.add(tailV > 0 ? "brow.tail.too_high" : "brow.tail.too_low", value: tailV, side: side, values: mm(tailV))
            let archU = rs.archU - ts.archU
            record.add(archU > 0 ? "brow.arch.too_outer" : "brow.arch.too_inner", value: archU, side: side, values: mm(archU))
            let archH = rs.archHeight - ts.archHeight
            record.add(archH > 0 ? "brow.arch.too_high" : "brow.arch.too_flat", value: archH, side: side, values: mm(archH))
            func angles(_ d: Double, _ v: Double, _ target: Double) -> [String: String] {
                ["delta": FeedbackComposer.degrees(d), "value": FeedbackComposer.degrees(v), "target": FeedbackComposer.degrees(target)]
            }
            let rise = rs.rise - ts.rise
            record.add(rise > 0 ? "brow.rise_angle.too_steep" : "brow.rise_angle.too_flat", value: rise, side: side, values: angles(rise, rs.rise, ts.rise))
            let fall = rs.fall - ts.fall
            record.add(fall > 0 ? "brow.tail_angle.too_steep" : "brow.tail_angle.too_level", value: fall, side: side, values: angles(fall, rs.fall, ts.fall))

            // Thickness and fill per third of the target: head, body, tail.
            let third = ts.length / 3
            let parts = [("head", ts.start...(ts.start + third)), ("body", (ts.start + third)...(ts.start + 2 * third)), ("tail", (ts.start + 2 * third)...ts.end)]
            let spacing = 1.0
            let thick = parts.compactMap { name, range -> (String, Double)? in
                guard let a = r.thickness(in: range, spacing: spacing), let b = t.thickness(in: range, spacing: spacing) else { return nil }
                return (name, a - b)
            }
            if let worst = thick.max(by: { abs($0.1) < abs($1.1) }) {
                record.add(worst.1 > 0 ? "brow.thickness.too_thick" : "brow.thickness.too_thin", value: worst.1, side: side,
                           values: ["delta": FeedbackComposer.mm(worst.1), "zone": zones[worst.0] ?? worst.0])
            }
            let browIndices = Set(brow.map(\.i))
            let fill = parts.map { name, range -> (String, Double) in
                let inPart = t.samples.filter { range.contains($0.local.x) }
                let a = inPart.reduce(0) { $0 + $1.area }
                return (name, a > 0 ? inPart.filter { browIndices.contains($0.index) }.reduce(0) { $0 + $1.area } / a : 1)
            }
            let coverage = t.samples.filter { browIndices.contains($0.index) }.reduce(0) { $0 + $1.area } / max(t.area, 1) * 100
            let emptiest = fill.min { $0.1 < $1.1 }?.0 ?? "body"
            record.add("brow.coverage.low", value: coverage, side: side,
                       values: ["value": FeedbackComposer.percent(coverage), "zone": zones[emptiest] ?? emptiest], size: 100 - coverage)

            // Darkness where the brow landed inside the target, against the virtual brow on the same spots (a brow drawn
            // in the wrong place is a placement message, not "too light").
            let landed = t.samples.filter { browIndices.contains($0.index) }
            let landedArea = landed.reduce(0) { $0 + $1.area }
            let inside = landed.map { max(skinNow - afterL($0.index), 0) * $0.area }.reduce(0, +) / max(landedArea, 1)
            let shownThere = landed.map { $0.dark * $0.area }.reduce(0, +) / max(landedArea, 1)
            let ratio = shownThere > 0 && landedArea > 0 ? inside / shownThere : 1
            record.add(ratio > 1 ? "brow.darkness.too_dark" : "brow.darkness.too_light", value: ratio, side: side,
                       values: ["value": ratio > 1 ? FeedbackComposer.times(ratio) : FeedbackComposer.percent(ratio * 100)],
                       size: abs(log(max(ratio, 0.01))))

            // Product outside the target outline (natural hairs that were already there do not count).
            var above = 0.0, below = 0.0, inner = 0.0
            for s in nearby where product.contains(s.i) && !targetIndices.contains(s.i) {
                let a = Double(before.samples[s.i].area)
                if s.local.x < ts.start - 2 { inner += a; continue }
                guard let column = t.column(at: s.local.x) else { continue }
                if s.local.y > column.upper + 1.5 { above += a } else if s.local.y < column.lower - 1.5 { below += a }
            }
            for (id, value) in [("brow.spill.above", above), ("brow.spill.below", below), ("brow.spill.inner", inner)] {
                let pct = value / max(t.area, 1) * 100
                record.add(id, value: pct, side: side, values: ["value": FeedbackComposer.percent(pct)])
            }

            // Calibration choice (not in the database): when head and tail are both off the same way, the whole brow is
            // shifted; its gap and spill on that side follow from it, so only the shift is told.
            let shifted = [("brow.head.too_high", "brow.tail.too_high", "brow.spill.above"), ("brow.head.too_low", "brow.tail.too_low", "brow.spill.below")]
            for (headRule, tailRule, spill) in shifted
            where record.hits.contains(where: { $0.rule == headRule && $0.side == side && $0.band != .ok })
                && record.hits.contains(where: { $0.rule == tailRule && $0.side == side && $0.band != .ok }) {
                record.hits.removeAll { $0.side == side && [spill, "brow.coverage.low", "brow.darkness.too_light"].contains($0.rule) }
            }

            let headPoint = frame.origin + frame.u * rs.start + frame.v * rs.head
            let tailPoint = frame.origin + frame.u * rs.end + frame.v * rs.tail
            measured[side] = Measured(shape: rs, headY: headPoint.y, tailY: tailPoint.y,
                                      thickness: r.thickness(in: rs.start...rs.end, spacing: spacing) ?? 0, darkness: r.darkness)
        }

        // Left against right.
        if let l = measured[.left], let r = measured[.right] {
            func diff(_ id: String, _ d: Double) {
                let (side, values) = FeedbackRecorder.pairValues(composer, higherIsLeft: d > 0, ["delta": FeedbackComposer.mm(d)])
                record.add(id, value: d, side: side, values: values)
            }
            func ratio(_ id: String, _ a: Double, _ b: Double) {
                guard a > 0, b > 0 else { return }
                let (side, values) = FeedbackRecorder.pairValues(composer, higherIsLeft: a > b, ["value": FeedbackComposer.times(max(a / b, b / a))])
                record.add(id, value: a / b, side: side, values: values)
            }
            if !record.notOK("brow.head.too_high") && !record.notOK("brow.head.too_low") { diff("brow.symmetry.head_height", l.headY - r.headY) }
            if !record.notOK("brow.arch.too_high") && !record.notOK("brow.arch.too_flat") {
                diff("brow.symmetry.arch_height", l.shape.archHeight - r.shape.archHeight)
            }
            if !record.notOK("brow.tail.too_high") && !record.notOK("brow.tail.too_low") { diff("brow.symmetry.tail_height", l.tailY - r.tailY) }
            ratio("brow.symmetry.length", l.shape.length, r.shape.length)
            ratio("brow.symmetry.thickness", l.thickness, r.thickness)
            ratio("brow.symmetry.darkness", l.darkness, r.darkness)
        }

        let tool = database.tools.brow
        var praise: [MakeupFeedback.Item] = []
        if !measured.isEmpty, !["brow.head", "brow.tail", "brow.arch"].contains(where: record.notOK) {
            praise += [composer.praise("brow.praise.shape", tool: tool, values: ["value": "2"])].compactMap { $0 }
        }
        if !measured.isEmpty, !record.notOK("brow.coverage"), !record.notOK("brow.darkness") {
            praise += [composer.praise("brow.praise.fill", tool: tool)].compactMap { $0 }
        }
        if measured.count == 2, !record.notOK("brow.symmetry") { praise += [composer.praise("brow.praise.balance", tool: tool)].compactMap { $0 } }
        return record.feedback(composer, praise: praise, notes: check.notes)
    }
}
