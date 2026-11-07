import Foundation

struct LowerLineSpec: Equatable {
    var enabled: Bool
    var extent: Double      // fraction of the lower lash line, measured from the outer corner inward
    var thickness: Double   // fraction of eye width
}

/// One eyeliner look in the spike's units: every length is a fraction of the eye width, angles are degrees.
/// `LinerStyle` (the catalog's model) converts one to one, so the catalog, the eye-shape planner and the overlay
/// share their numbers. `WingOrigin` and `WingBase` are the app's own enums.
struct LinerSpec: Equatable {
    var upperStart: Double              // 0...1 along the lash line from the inner corner
    var upperThickness: [Double]        // [inner, mid, outer]
    var tightline: Bool
    var wingAngleDeg: Double            // positive = lifts upward
    var wingLength: Double
    var wingTargetsBrowTail: Bool
    var lowerLine: LowerLineSpec
    var wingOrigin: WingOrigin
    var wingBase: WingBase
    var innerExtension: Double = 0      // extra line past the inner corner, toward the nose

    init(upperStart: Double = 0, upperThickness: [Double] = [0.02, 0.02, 0.02], tightline: Bool = false,
         wingAngleDeg: Double = 0, wingLength: Double = 0, wingTargetsBrowTail: Bool = false,
         lowerLine: LowerLineSpec = LowerLineSpec(enabled: false, extent: 0.5, thickness: 0.015),
         wingOrigin: WingOrigin = .outerCorner, wingBase: WingBase = .lowerLidTangent) {
        self.upperStart = upperStart
        self.upperThickness = Array((upperThickness + [0, 0, 0]).prefix(3))
        self.tightline = tightline
        self.wingAngleDeg = wingAngleDeg
        self.wingLength = wingLength
        self.wingTargetsBrowTail = wingTargetsBrowTail
        self.lowerLine = lowerLine
        self.wingOrigin = wingOrigin
        self.wingBase = wingBase
    }

    init(style: LinerStyle) {
        self.init(upperStart: Double(style.start),
                  upperThickness: [Double(style.innerWidth),
                                   Double(style.midWidth ?? (style.innerWidth + style.outerWidth) / 2),
                                   Double(style.outerWidth)],
                  tightline: style.tightline, wingAngleDeg: Double(style.wingAngle),
                  wingLength: Double(style.wingLength), wingTargetsBrowTail: style.wingTargetsBrowTail,
                  lowerLine: LowerLineSpec(enabled: style.lowerLine.enabled, extent: Double(style.lowerLine.extent),
                                           thickness: Double(style.lowerLine.thickness)),
                  wingOrigin: style.wingOrigin, wingBase: style.wingBase)
        innerExtension = Double(style.innerExtension)
    }
}
