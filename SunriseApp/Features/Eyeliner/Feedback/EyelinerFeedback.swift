// -Nimah: eyeliner feedback. The target is the liner drawn on the desired-look photo: mesh samples at least 15 L* darker
// there than on the bare face (lashes and lid shadow are in both, so they cancel). The result is what got as dark in the
// result photo. Both are compared in a frame along the target line, per third (inner, middle, outer) and for the wing.
// Rules and texts: `makeup-feedback.database.json` (eyeliner). Not measured yet: lash gap, wobble, blunt or detached
// wing, the Arabian lower line.
import Foundation
import simd

enum EyelinerFeedback {
    /// `detection.makeup_mask.eyeliner`: dL* <= -15 against the bare face.
    static let linerDark = 15.0

    struct Measured { var wingAngle: Double?; var wingLength: Double; var tipY: Double; var thickness: Double }

    static func evaluate(_ input: LineFeedbackInput, database: FeedbackDatabase, language: FeedbackLanguage) -> MakeupFeedback {
        var composer = FeedbackComposer(database: database, language: language)
        composer.part = \.eye
        guard input.hadBeforePhoto else { return BlushFeedback.noBeforePhoto(composer) }
        var check = FeedbackPhotoCheck(before: input.before, after: input.after, tool: "eyeliner", composer: composer)
        guard check.blocking.isEmpty, let before = input.before, let after = input.after,
              before.samples.count == after.samples.count, !before.samples.isEmpty else {
            return MakeupFeedback(score: nil, headline: "", comments: [], items: check.blocking.isEmpty ? check.notes : check.blocking)
        }
        let both = before.samples.indices.filter { before.samples[$0].visible && after.samples[$0].visible }
        let light = FeedbackSkin.shift(before: before, after: after, both: both)
        if light.mismatch { check.report("capture.lighting_mismatch", tool: "eyeliner", composer) }
        func bare(_ i: Int) -> Double { Double(before.samples[i].lab.x) }
        func now(_ i: Int) -> Double { Double(after.samples[i].lab.x + light.shift.x) }
        func point(_ i: Int) -> SIMD2<Double> { SIMD2(Double(before.samples[i].position.x), Double(before.samples[i].position.y)) }
        let hasWing = input.look != "natural"

        var record = FeedbackRecorder(database: database, scale: Double(before.ipd > 40 ? before.ipd / 63 : 1), look: input.look)
        let zones = database.words(language).liner_zone
        var measured: [FeedbackSide: Measured] = [:]
        for sign in [1.0, -1.0] {
            let side: FeedbackSide = sign > 0 ? .left : .right
            let area = both.filter {
                let p = before.samples[$0].position
                return Double(p.x) * sign > 6 && abs(p.x) < 65 && abs(p.y - before.eyeY) < 10
            }
            let target = area.compactMap { i -> (Int, Double)? in
                guard let shown = before.samples[i].rendered else { return nil }
                let dark = bare(i) - Double(shown.x)
                return dark >= linerDark ? (i, dark) : nil
            }
            guard let frame = LineFrame(points: target.map { (point($0.0), Double(before.samples[$0.0].area)) }) else { continue }
            let t = LineProfile(target.map { LineSample(local: frame.local(point($0.0)), area: Double(before.samples[$0.0].area), dark: $0.1, index: $0.0) }, bin: 1)
            guard let tStart = t.start, let tEnd = t.end, tEnd - tStart > 4 else { continue }
            let length = tEnd - tStart
            let lowest = t.columns.values.map(\.lower).min() ?? 0, highest = t.columns.values.map(\.upper).max() ?? 0
            let nearby = area.map { (i: $0, local: frame.local(point($0))) }.filter {
                $0.local.x > tStart - 6 && $0.local.x < tEnd + 8 && $0.local.y > lowest - 5 && $0.local.y < highest + 5
            }
            let liner = nearby.filter { bare($0.i) - now($0.i) >= linerDark }
            let r = LineProfile(liner.map { LineSample(local: $0.local, area: Double(before.samples[$0.i].area), dark: bare($0.i) - now($0.i), index: $0.i) }, bin: 1)
            // Share of the target path (its columns) with liner on it.
            let targetColumns = Set(t.columns.keys), covered = targetColumns.filter { r.columns[$0] != nil }
            let coverage = targetColumns.isEmpty ? 0 : Double(covered.count) / Double(targetColumns.count) * 100
            guard coverage >= 15, let rStart = r.start, let rEnd = r.end else {
                record.fire("eyeliner.none", side: side)
                record.inputs.add("placement", "key_point_offset_mm", 10.5 * record.scale); record.inputs.add("shade", "darkness_ratio", 3)
                continue
            }

            let startDelta = rStart - tStart
            record.add(startDelta < 0 ? "eyeliner.start.too_early" : "eyeliner.start.too_late", value: startDelta, side: side,
                       values: ["delta": FeedbackComposer.mm(startDelta)])

            let third = length / 3
            let parts = [("inner", tStart...(tStart + third)), ("middle", (tStart + third)...(tStart + 2 * third)), ("outer", (tStart + 2 * third)...tEnd)]
            let missing = parts.map { name, range -> (String, Int) in
                (name, targetColumns.filter { range.contains((Double($0) + 0.5) * t.bin) && r.columns[$0] == nil }.count)
            }
            let broken = missing.max { $0.1 < $1.1 }?.0 ?? "middle"
            record.add("eyeliner.coverage.low", value: coverage, side: side,
                       values: ["value": FeedbackComposer.percent(coverage), "zone": zones[broken] ?? broken], size: 100 - coverage)
            let spacing = 0.5
            let thick = parts.compactMap { name, range -> (String, Double)? in
                guard let a = r.thickness(in: range, spacing: spacing), let b = t.thickness(in: range, spacing: spacing) else { return nil }
                return (name, a - b)
            }
            if let worst = thick.max(by: { abs($0.1) < abs($1.1) }) {
                record.inputs.add("shade", "thickness_mm", worst.1)
                record.add(worst.1 > 0 ? "eyeliner.thickness.too_thick" : "eyeliner.thickness.too_thin", value: worst.1, side: side,
                           values: ["delta": FeedbackComposer.mm(worst.1), "zone": zones[worst.0] ?? worst.0])
            }
            let inside = t.samples.map { max(bare($0.index) - now($0.index), 0) * $0.area }.reduce(0, +) / max(t.area, 1)
            let ratio = t.darkness > 0 ? min(inside / t.darkness, 1) : 1
            record.inputs.add("shade", "darkness_ratio", 1 / max(ratio, 0.01) - 1)
            record.add("eyeliner.darkness.too_light", value: ratio, side: side, values: ["value": FeedbackComposer.percent(ratio * 100)],
                       size: abs(log(max(ratio, 0.01))))

            // Liner outside the target line, above (on the lid) and below.
            let targetIndices = Set(t.samples.map(\.index))
            var above = 0.0, below = 0.0
            for s in liner where !targetIndices.contains(s.i) {
                guard let column = t.column(at: s.local.x) else { continue }
                let a = Double(before.samples[s.i].area)
                if s.local.y > column.upper + 0.8 { above += a } else if s.local.y < column.lower - 0.8 { below += a }
            }
            for (id, value) in [("eyeliner.smudge.above", above), ("eyeliner.smudge.below", below)] {
                let pct = value / max(t.area, 1) * 100
                record.add(id, value: pct, side: side, values: ["value": FeedbackComposer.percent(pct)])
            }

            // The wing: the outer quarter of the line, its angle against the face's horizontal, its reach and its tip.
            let wingFrom = tStart + 0.75 * length
            func wingAngle(_ p: LineProfile) -> Double? {
                let points = p.columns.filter { (Double($0.key) + 0.5) * p.bin >= wingFrom }
                    .map { (u: (Double($0.key) + 0.5) * p.bin, v: ($0.value.lower + $0.value.upper) / 2) }
                guard points.count >= 3 else { return nil }
                let mu = points.reduce(0) { $0 + $1.u } / Double(points.count), mv = points.reduce(0) { $0 + $1.v } / Double(points.count)
                let slope = points.reduce(0) { $0 + ($1.u - mu) * ($1.v - mv) } / max(points.reduce(0) { $0 + ($1.u - mu) * ($1.u - mu) }, 0.001)
                let face = frame.u + frame.v * slope
                return atan2(face.y, abs(face.x)) * 180 / .pi
            }
            func tip(_ p: LineProfile, _ end: Double) -> Double {
                let c = p.column(at: end - 0.01) ?? p.column(at: end - p.bin)
                let v = c.map { ($0.lower + $0.upper) / 2 } ?? 0
                return (frame.origin + frame.u * end + frame.v * v).y
            }
            let rAngle = wingAngle(r), tAngle = wingAngle(t)
            var keyPoints = [startDelta]
            if hasWing { keyPoints += [rEnd - tEnd, tip(r, rEnd) - tip(t, tEnd)] }
            record.inputs.add("placement", "key_point_offset_mm", keyPoints.map(abs).reduce(0, +) / Double(keyPoints.count))
            if hasWing, let rAngle, let tAngle { record.inputs.add("placement", "wing_angle_deg", rAngle - tAngle) }
            if hasWing {
                if let rAngle, let tAngle {
                    let d = rAngle - tAngle
                    record.add(d > 0 ? "eyeliner.wing.too_steep" : "eyeliner.wing.too_flat", value: d, side: side,
                               values: ["delta": FeedbackComposer.degrees(d), "value": FeedbackComposer.degrees(rAngle), "target": FeedbackComposer.degrees(tAngle)])
                }
                let reach = rEnd - tEnd
                record.add(reach > 0 ? "eyeliner.wing.too_long" : "eyeliner.wing.too_short", value: reach, side: side,
                           values: ["delta": FeedbackComposer.mm(reach)])
                let tipDelta = tip(r, rEnd) - tip(t, tEnd)
                record.add(tipDelta > 0 ? "eyeliner.wing_tip.too_high" : "eyeliner.wing_tip.too_low", value: tipDelta, side: side,
                           values: ["delta": FeedbackComposer.mm(tipDelta)])
            }
            measured[side] = Measured(wingAngle: rAngle, wingLength: rEnd - wingFrom, tipY: tip(r, rEnd),
                                      thickness: r.thickness(in: rStart...rEnd, spacing: spacing) ?? 0)
        }

        if let l = measured[.left], let r = measured[.right] {
            func diff(_ id: String, _ d: Double, _ format: (Double) -> String) {
                let (side, values) = FeedbackRecorder.pairValues(composer, higherIsLeft: d > 0, ["delta": format(d)])
                record.add(id, value: d, side: side, values: values)
            }
            if hasWing {
                if let a = l.wingAngle, let b = r.wingAngle { diff("eyeliner.symmetry.wing_angle", a - b, FeedbackComposer.degrees) }
                diff("eyeliner.symmetry.wing_length", l.wingLength - r.wingLength, FeedbackComposer.mm)
                diff("eyeliner.symmetry.tip_height", l.tipY - r.tipY, FeedbackComposer.mm)
            }
            if l.thickness > 0, r.thickness > 0 {
                let (side, values) = FeedbackRecorder.pairValues(composer, higherIsLeft: l.thickness > r.thickness,
                                                                 ["value": FeedbackComposer.times(max(l.thickness / r.thickness, r.thickness / l.thickness))])
                record.add("eyeliner.symmetry.thickness", value: l.thickness / r.thickness, side: side, values: values)
            }
        }

        let tool = database.tools.eyeliner
        var praise: [MakeupFeedback.Item] = []
        if !measured.isEmpty, !record.notOK("eyeliner.coverage"), !record.notOK("eyeliner.thickness") {
            praise += [composer.praise("eyeliner.praise.line", tool: tool)].compactMap { $0 }
        }
        if hasWing, !measured.isEmpty, !record.notOK("eyeliner.wing") {
            praise += [composer.praise("eyeliner.praise.wing", tool: tool, values: ["value": "3"])].compactMap { $0 }
        }
        if measured.count == 2, !record.notOK("eyeliner.symmetry") { praise += [composer.praise("eyeliner.praise.balance", tool: tool)].compactMap { $0 } }
        return record.feedback(composer, tool: "eyeliner", praise: praise, notes: check.notes)
    }
}
