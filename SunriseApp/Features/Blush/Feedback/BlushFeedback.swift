// -Nimah: blush feedback v2. Compares the bare face of the desired-look photo with the result photo, sample by sample on
// the ARKit face mesh, inside the target area the engine drew on the desired-look photo. Rules and texts come from
// `makeup-feedback.database.json` (blush). Not measured yet: angle, edge softness, Lifted temple reach, Sunkissed nose band.
import CoreGraphics
import Foundation
import simd

struct BlushFeedbackInput: Sendable {
    /// The desired-look photo: bare colours, the colours shown with the virtual blush, and the target outlines.
    var before: FaceScan?
    /// True when a desired-look photo exists even if its face could not be measured.
    var hadBeforePhoto: Bool
    var after: FaceScan?
    var style: BlushPlacementStyle?
    /// The chosen shade, sRGB 0...1.
    var shade: SIMD3<Double>?
}

enum BlushFeedback {
    /// Ratio of the tutorial's outer line to the full pigment field (`target_geometry.blush`).
    static let outerScale: CGFloat = 0.82
    /// Blush = chroma rise and colour difference at least this large. Database: 4 and 3; raised after the first device
    /// test (2026-11-09), where a bare cheek read as blush once the head was tilted and the light fell differently.
    static let minimumChromaRise: Float = 6, minimumDifference: Float = 5

    static func evaluate(_ input: BlushFeedbackInput, database: FeedbackDatabase, language: FeedbackLanguage) -> MakeupFeedback {
        let composer = FeedbackComposer(database: database, language: language)

        // 1. Photo checks. A blocking one stops the measuring and asks for a retake.
        guard input.hadBeforePhoto else { return noBeforePhoto(composer) }
        var check = FeedbackPhotoCheck(before: input.before, after: input.after, tool: "blush", composer: composer)
        guard check.blocking.isEmpty, let before = input.before, let after = input.after,
              before.samples.count == after.samples.count, !before.samples.isEmpty else {
            return MakeupFeedback(score: nil, headline: "", comments: [], items: check.blocking.isEmpty ? check.notes : check.blocking)
        }

        // 2. Same light in both photos: shift the result's colours so the forehead and chin match.
        let both = before.samples.indices.filter { before.samples[$0].visible && after.samples[$0].visible }
        let light = FeedbackSkin.shift(before: before, after: after, both: both)
        let shift = light.shift
        if light.mismatch { check.report("capture.lighting_mismatch", tool: "blush", composer) }

        // 3. Each cheek against its target.
        guard let outline = before.outline ?? after.outline, !outline.cheeks.isEmpty else {
            check.report("capture.no_face", ["photo": "Try On"], tool: "blush", composer)
            return MakeupFeedback(score: nil, headline: "", comments: [], items: check.blocking + check.notes)
        }
        let screens = before.outline != nil ? before.samples.map(\.screen) : after.samples.map(\.screen)
        let shadeHue = input.shade.map { s -> Float in
            let lab = FeedbackColor.lab(sRGB: s.x, s.y, s.z)
            return FeedbackColor.hue(a: lab.y, b: lab.z)
        }
        let cheeks = outline.cheeks.compactMap { cheek in
            measure(cheek: cheek, screens: screens, both: both, before: before, after: after, shift: shift, shadeHue: shadeHue)
        }
        var hits: [FeedbackHit] = [], entries: [FeedbackScoreEntry] = []
        let scale = Double(before.ipd > 40 ? before.ipd / 63 : 1)
        let look = input.style?.rawValue
        func applies(_ rule: FeedbackDatabase.Rule) -> Bool {
            if let looks = rule.looks, !looks.contains(look ?? "") { return false }
            if let excluded = rule.not_for_looks, let look, excluded.contains(look) { return false }
            return true
        }
        func add(_ id: String, value: Double, side: FeedbackSide, size: Double, values: [String: String], scaled: Bool = false) {
            guard let rule = database.rule(id), applies(rule), let t = rule.thresholds else { return }
            let band = FeedbackBand.of(value, kind: rule.kind, t, scale: scaled && rule.scale == "ipd" ? scale : 1)
            entries.append(FeedbackScoreEntry(band: band, weight: rule.weight, priority: rule.priority))
            hits.append(FeedbackHit(rule: id, band: band, side: side, priority: rule.priority, values: values, size: size,
                                    suppresses: rule.suppresses ?? []))
        }
        let zoneWords = database.words(language).blush_zone
        for c in cheeks {
            if c.coverage < 10, let rule = database.rule("blush.none") {
                entries.append(FeedbackScoreEntry(band: .large, weight: rule.weight, priority: rule.priority))
                hits.append(FeedbackHit(rule: rule.id, band: .large, side: c.side, priority: rule.priority, values: [:],
                                        size: 100 - c.coverage, suppresses: rule.suppresses ?? []))
                continue
            }
            add(c.vertical > 0 ? "blush.offset.too_high" : "blush.offset.too_low", value: c.vertical, side: c.side,
                size: abs(c.vertical), values: ["delta": FeedbackComposer.mm(c.vertical)], scaled: true)
            add(c.lateral > 0 ? "blush.offset.too_far_out" : "blush.offset.too_far_in", value: c.lateral, side: c.side,
                size: abs(c.lateral), values: ["delta": FeedbackComposer.mm(c.lateral)], scaled: true)
            add(c.areaRatio > 1 ? "blush.size.too_large" : "blush.size.too_small", value: c.areaRatio, side: c.side,
                size: abs(log(max(c.areaRatio, 0.01))),
                values: ["value": c.areaRatio > 1 ? FeedbackComposer.times(c.areaRatio) : FeedbackComposer.percent(c.areaRatio * 100)])
            add("blush.coverage.low", value: c.coverage, side: c.side, size: 100 - c.coverage,
                values: ["value": FeedbackComposer.percent(c.coverage), "zone": zoneWords[c.barestZone] ?? c.barestZone])
            if let ratio = c.intensityRatio {
                add(ratio > 1 ? "blush.intensity.too_heavy" : "blush.intensity.too_light", value: ratio, side: c.side,
                    size: abs(log(ratio)),
                    values: ["value": ratio > 1 ? FeedbackComposer.times(ratio) : FeedbackComposer.percent(ratio * 100)])
            }
            for (zone, pct) in c.spill {
                add("blush.spill.\(zone)", value: pct, side: c.side, size: pct, values: ["value": FeedbackComposer.percent(pct)])
            }
            if let cv = c.patchiness {
                add("blush.patchy", value: cv, side: c.side, size: cv, values: ["zone": zoneWords[c.strongestZone] ?? c.strongestZone])
            }
            if let hue = c.hueDelta {
                add(hue > 0 ? "blush.hue.warmer" : "blush.hue.cooler", value: hue, side: c.side, size: abs(hue),
                    values: ["delta": FeedbackComposer.degrees(hue)])
            }
        }

        // 4. Left against right.
        let cheekWords = database.words(language).cheek
        let measured = cheeks.filter { $0.coverage >= 10 }
        if let left = measured.first(where: { $0.side == .left }), let right = measured.first(where: { $0.side == .right }) {
            func pair(_ id: String, _ value: Double, higherIsLeft: Bool, values: [String: String]) {
                let higher: FeedbackSide = higherIsLeft ? .left : .right, other: FeedbackSide = higherIsLeft ? .right : .left
                add(id, value: value, side: higher, size: abs(value),
                    values: values.merging(["other": cheekWords[other.rawValue] ?? ""]) { $1 }, scaled: true)
            }
            // `suppressed_by`: a cheek already told it is too high or too low.
            let offsetHit = hits.contains { ($0.rule == "blush.offset.too_high" || $0.rule == "blush.offset.too_low") && $0.band != .ok }
            if !offsetHit {
                let d = left.vertical - right.vertical
                pair("blush.symmetry.height", d, higherIsLeft: d > 0, values: ["delta": FeedbackComposer.mm(d)])
            }
            if left.strength > 0, right.strength > 0 {
                let r = left.strength / right.strength
                pair("blush.symmetry.strength", r, higherIsLeft: r > 1, values: ["value": FeedbackComposer.times(max(r, 1 / r))])
            }
            if left.area > 0, right.area > 0 {
                let r = left.area / right.area
                pair("blush.symmetry.size", r, higherIsLeft: r > 1, values: ["value": FeedbackComposer.times(max(r, 1 / r))])
            }
        }

        // 5. What to show: the worst few, or praise when everything is within tolerance.
        var items: [MakeupFeedback.Item] = []
        do {
            let praise = database.tools.blush.praise
            let placementOK = !hits.contains { ($0.rule.hasPrefix("blush.offset") || $0.rule.hasPrefix("blush.size")) && $0.band != .ok }
            let worst = measured.map { max(abs($0.vertical), abs($0.lateral)) }.max() ?? 0
            if placementOK, let p = praise.first(where: { $0.id == "blush.praise.placement" }) {
                let text = p.message.text(language)
                items.append(.init(title: text.title,
                                   say: composer.fill(text.say, ["part": cheekWords["both"] ?? "", "value": FeedbackComposer.mm(max(worst, 0.5))]),
                                   steps: [], band: .ok, rule: p.id))
            }
            if !hits.contains(where: { $0.rule.hasPrefix("blush.symmetry") && $0.band != .ok }), measured.count == 2,
               let p = praise.first(where: { $0.id == "blush.praise.balance" }) {
                let text = p.message.text(language)
                items.append(.init(title: text.title, say: text.say, steps: [], band: .ok, rule: p.id))
            }
        }
        return composer.assemble(hits: hits, entries: entries, praise: items, notes: check.notes)
    }

    // MARK: Measuring one cheek

    struct Cheek {
        var side: FeedbackSide
        /// Percent of the target area with blush.
        var coverage: Double
        /// Blush centre minus target centre, mm: up, and outward (towards the ear).
        var vertical: Double, lateral: Double
        var areaRatio: Double
        var intensityRatio: Double?
        /// Spill past the full pigment field, percent of the target area, per database zone.
        var spill: [(String, Double)]
        var patchiness: Double?
        var hueDelta: Double?
        var barestZone: String, strongestZone: String
        /// Mean colour change inside the target, and blush area (mm²), for left/right comparison.
        var strength: Double, area: Double
    }

    static func measure(cheek: BlushGuideSnapshot.Cheek, screens: [CGPoint], both: [Int], before: FaceScan, after: FaceScan,
                        shift: Lab, shadeHue: Float?) -> Cheek? {
        let limit = cheek.outer.map { p in
            CGPoint(x: cheek.center.x + (p.x - cheek.center.x) / outerScale, y: cheek.center.y + (p.y - cheek.center.y) / outerScale)
        }
        let area = both.filter { contains(cheek.outer, screens[$0]) }
        guard area.count >= 8 else { return nil }
        let core = Set(both.filter { contains(cheek.inner, screens[$0]) })
        let inside = Set(both.filter { contains(limit, screens[$0]) })
        let targetArea = area.reduce(0) { $0 + Double(before.samples[$1].area) }
        let t = area.reduce(SIMD2<Double>.zero) {
            let s = before.samples[$1]; return $0 + SIMD2(Double(s.position.x), Double(s.position.y)) * Double(s.area)
        } / targetArea
        let sign: Double = t.x >= 0 ? 1 : -1
        let radius = (targetArea / .pi).squareRoot()
        func local(_ i: Int) -> SIMD2<Double> {
            let p = before.samples[i].position
            return SIMD2(abs(Double(p.x)) - abs(t.x), Double(p.y) - t.y)
        }
        let zone = both.filter {
            Double(before.samples[$0].position.x) * sign > 0 && simd_length(local($0)) <= 2.5 * radius
        }
        // This cheek's own light: the skin around the field (outside the limit) should not change between the photos, so
        // its median change is taken out. Forehead and chin alone missed light that fell differently on one cheek.
        var cheekShift = shift
        let ring = zone.filter { !inside.contains($0) }
        if ring.count >= 15 {
            func median(_ values: [Float]) -> Float { let s = values.sorted(); return s[s.count / 2] }
            let d = ring.map { before.samples[$0].lab - (after.samples[$0].lab + shift) }
            cheekShift = shift + Lab(median(d.map(\.x)), median(d.map(\.y)), median(d.map(\.z)))
        }
        // The blush: a clear rise in chroma, in the shade's direction (`detection.makeup_mask.blush`).
        var change: [Int: Float] = [:], blush = Set<Int>(), hueVector: [Int: SIMD2<Float>] = [:]
        for i in zone {
            let b = before.samples[i].lab, a = after.samples[i].lab + cheekShift
            let dc = FeedbackColor.chroma(a) - FeedbackColor.chroma(b)
            let dab = SIMD2(a.y - b.y, a.z - b.z)
            change[i] = dc; hueVector[i] = dab
            let hueOK = shadeHue.map { abs(FeedbackColor.hueDifference(FeedbackColor.hue(a: dab.x, b: dab.y), $0)) <= 60 } ?? true
            if dc >= minimumChromaRise && FeedbackColor.deltaE2000(b, a) >= minimumDifference && hueOK { blush.insert(i) }
        }
        func areaOf<S: Sequence>(_ s: S) -> Double where S.Element == Int { s.reduce(0) { $0 + Double(before.samples[$1].area) } }
        let coverage = areaOf(area.filter(blush.contains)) / targetArea * 100

        let weights = blush.map { (i: $0, w: Double(max(change[$0] ?? 0, 0))) }
        let total = weights.reduce(0) { $0 + $1.w }
        let centre = total > 0 ? weights.reduce(SIMD2<Double>.zero) { $0 + local($1.i) * $1.w } / total : .zero

        // Zones of the target, for "the inner part is still bare" and "stronger at the top".
        func targetZone(_ i: Int) -> String {
            let p = local(i)
            if simd_length(p) < 0.4 * radius { return "center" }
            return abs(p.x) > abs(p.y) ? (p.x > 0 ? "outer" : "inner") : (p.y > 0 ? "upper" : "lower")
        }
        var zoneCover: [String: (blush: Double, all: Double, change: Double)] = [:]
        for i in area {
            let z = targetZone(i), a = Double(before.samples[i].area)
            var v = zoneCover[z] ?? (0, 0, 0)
            v.all += a; if blush.contains(i) { v.blush += a }; v.change += Double(max(change[i] ?? 0, 0)) * a
            zoneCover[z] = v
        }
        let barest = zoneCover.min { $0.value.blush / $0.value.all < $1.value.blush / $1.value.all }?.key ?? "center"
        let strongest = zoneCover.max { $0.value.change / $0.value.all < $1.value.change / $1.value.all }?.key ?? "center"

        // Strength against what the virtual blush showed on the same spots of the desired-look photo.
        var intensity: Double?
        let shown = core.compactMap { i -> Float? in
            before.samples[i].rendered.map { FeedbackColor.chroma($0) - FeedbackColor.chroma(before.samples[i].lab) }
        }
        let inCore = core.filter(blush.contains)
        if shown.count >= 5, !inCore.isEmpty {
            let target = Double(shown.reduce(0, +)) / Double(shown.count)
            let real = Double(inCore.reduce(Float(0)) { $0 + (change[$1] ?? 0) }) / Double(inCore.count)
            if target > 2 { intensity = real / target }
        }

        // Spill past the full field, by direction from the target centre.
        var spill: [String: Double] = ["eye": 0, "nose": 0, "mouth": 0, "ear": 0, "jaw": 0]
        for i in blush where !inside.contains(i) {
            let p = local(i), angle = atan2(p.y, p.x) * 180 / .pi
            let z = angle > 45 && angle <= 135 ? "eye" : (angle > 135 || angle <= -150) ? "nose"
                : angle <= -90 ? "mouth" : angle <= -30 ? "jaw" : "ear"
            spill[z, default: 0] += Double(before.samples[i].area) / targetArea * 100
        }

        // Evenness inside the small circle, after a 3 mm blur.
        var patchiness: Double?
        let coreList = Array(core)
        if coreList.count >= 6 {
            let blurred = coreList.map { i -> Double in
                let near = coreList.filter { simd_distance(before.samples[$0].position, before.samples[i].position) <= 3 }
                return near.reduce(0) { $0 + Double(max(change[$1] ?? 0, 0)) } / Double(near.count)
            }
            let mean = blurred.reduce(0, +) / Double(blurred.count)
            if mean > 2 {
                let sd = (blurred.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(blurred.count)).squareRoot()
                patchiness = sd / mean
            }
        }

        // Colour: hue of the change against the chosen shade's hue (positive: warmer, towards orange).
        var hue: Double?
        let blushInArea = area.filter(blush.contains)
        if let shadeHue, blushInArea.count >= 5 {
            let v = blushInArea.reduce(SIMD2<Float>.zero) { $0 + (hueVector[$1] ?? .zero) } / Float(blushInArea.count)
            hue = Double(FeedbackColor.hueDifference(FeedbackColor.hue(a: v.x, b: v.y), shadeHue))
        }

        let blushArea = areaOf(blush)
        let strength = blushInArea.isEmpty ? 0
            : Double(blushInArea.reduce(Float(0)) { $0 + (change[$1] ?? 0) }) / Double(blushInArea.count)
        return Cheek(side: sign > 0 ? .left : .right, coverage: coverage,
                     vertical: total > 0 ? centre.y : 0, lateral: total > 0 ? centre.x : 0,
                     areaRatio: blushArea / targetArea, intensityRatio: intensity,
                     spill: ["eye", "nose", "mouth", "ear", "jaw"].map { ($0, spill[$0] ?? 0) },
                     patchiness: patchiness, hueDelta: hue, barestZone: barest, strongestZone: strongest,
                     strength: strength, area: blushArea)
    }

    static func noBeforePhoto(_ composer: FeedbackComposer) -> MakeupFeedback {
        var check = FeedbackPhotoCheck()
        check.report("capture.no_before_photo", tool: "", composer)
        return MakeupFeedback(score: nil, headline: "", comments: [], items: check.notes)
    }

    /// Point in polygon (even-odd).
    static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false, j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
