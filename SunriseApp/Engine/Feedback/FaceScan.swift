// -Nimah: what the feedback needs from one photo, measured at the shutter. Colours are sampled at fixed points of the
// ARKit face mesh, so the same sample is the same spot of skin in both photos whatever the head pose or distance.
// Memory only: no frame, mesh or picture is kept, only these numbers, and only for the current run.
@preconcurrency import ARKit
import UIKit
import simd

/// CIELAB colour, D65.
typealias Lab = SIMD3<Float>

struct FaceScan: Sendable {
    struct Sample: Sendable {
        /// Face-local millimetres: x towards the person's own left, y up, z out of the face.
        var position: SIMD3<Float>
        /// Skin area this sample stands for, mm².
        var area: Float
        /// The bare camera colour, decoded as the makeup engine decodes it (so it matches what the screen shows).
        var lab: Lab
        /// The colour drawn on screen with the virtual makeup, when the screen picture was read.
        var rendered: Lab?
        /// Where the sample is on screen, in the camera view's points.
        var screen: CGPoint
        /// Facing the camera and inside the picture.
        var visible: Bool
    }

    var samples: [Sample]
    /// Head pose relative to the camera, degrees. Yaw positive: the face points to the screen's right; pitch positive: looking down.
    var yaw: Float, pitch: Float, roll: Float
    /// ARKit blend shapes used by the photo checks.
    var blink: Float, smile: Float, jawOpen: Float, browRaise: Float
    /// Distance between the eye centres, mm (thresholds scale with it).
    var ipd: Float
    /// Height of the eye centres in face-local mm.
    var eyeY: Float
    /// The blush target outlines the engine drew on this frame, in the camera view's points.
    var outline: BlushGuideSnapshot?
    var viewport: CGSize
}

extension FaceScan {
    /// Six fixed points per mesh triangle, as barycentric weights. Same pattern for every photo.
    static let pattern: [SIMD3<Float>] = [
        SIMD3(2 / 3, 1 / 6, 1 / 6), SIMD3(1 / 6, 2 / 3, 1 / 6), SIMD3(1 / 6, 1 / 6, 2 / 3),
        SIMD3(1 / 6, 5 / 12, 5 / 12), SIMD3(5 / 12, 1 / 6, 5 / 12), SIMD3(5 / 12, 5 / 12, 1 / 6)
    ]

    /// Measures the face in the view's current camera frame. Nil when no face is tracked.
    @MainActor static func measure(view: ARSCNView, outline: BlushGuideSnapshot?, rendered: ScreenPixels?) -> FaceScan? {
        guard let frame = view.session.currentFrame,
              let face = frame.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first(where: \.isTracked) else { return nil }
        return measure(frame: frame, face: face, viewport: view.bounds.size, outline: outline, rendered: rendered)
    }

    static func measure(frame: ARFrame, face: ARFaceAnchor, viewport: CGSize, outline: BlushGuideSnapshot?,
                        rendered: ScreenPixels?) -> FaceScan {
        let geometry = face.geometry
        let vertices = geometry.vertices
        let indices = geometry.triangleIndices
        let anchor = face.transform
        let cameraPosition = SIMD3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y,
                                   frame.camera.transform.columns.3.z)
        let image = CameraPixels(frame.capturedImage)
        let rawSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage))
        func world(_ p: SIMD3<Float>) -> SIMD3<Float> { let w = anchor * SIMD4(p, 1); return SIMD3(w.x, w.y, w.z) }

        var samples: [Sample] = []
        samples.reserveCapacity(indices.count / 3 * pattern.count)
        image?.lock()
        for t in stride(from: 0, to: indices.count - 2, by: 3) {
            let a = vertices[Int(indices[t])], b = vertices[Int(indices[t + 1])], c = vertices[Int(indices[t + 2])]
            let cross = simd_cross(b - a, c - a)
            let area = simd_length(cross) * 0.5 * 1_000_000 / Float(pattern.count)
            let normalLocal = simd_normalize(cross)
            let normal = simd_normalize(SIMD3((anchor * SIMD4(normalLocal, 0)).x, (anchor * SIMD4(normalLocal, 0)).y,
                                              (anchor * SIMD4(normalLocal, 0)).z))
            for w in pattern {
                let local = a * w.x + b * w.y + c * w.z
                let p = world(local)
                let facing = simd_dot(normal, simd_normalize(cameraPosition - p))
                let screen = frame.camera.projectPoint(p, orientation: .portrait, viewportSize: viewport)
                let raw = frame.camera.projectPoint(p, orientation: .landscapeRight, viewportSize: rawSize)
                let inView = screen.x >= 0 && screen.y >= 0 && screen.x < viewport.width && screen.y < viewport.height
                let lab = image?.lab(at: raw) ?? .zero
                let shown = rendered?.lab(atViewPoint: screen, viewport: viewport)
                samples.append(Sample(position: local * 1000, area: area, lab: lab, rendered: shown, screen: screen,
                                      visible: facing > 0.35 && inView && image != nil))
            }
        }
        image?.unlock()

        // Pose from where the face points, as seen on screen.
        let origin = world(.zero), forward = world(SIMD3(0, 0, 0.05))
        let toCamera = simd_normalize(cameraPosition - origin)
        let faceAxis = simd_normalize(forward - origin)
        let tilt = acos(max(-1, min(1, simd_dot(faceAxis, toCamera)))) * 180 / .pi
        let o = frame.camera.projectPoint(origin, orientation: .portrait, viewportSize: viewport)
        let f = frame.camera.projectPoint(forward, orientation: .portrait, viewportSize: viewport)
        let d = CGVector(dx: f.x - o.x, dy: f.y - o.y), length = max(hypot(d.dx, d.dy), 0.0001)
        let leftEye = SIMD3(face.leftEyeTransform.columns.3.x, face.leftEyeTransform.columns.3.y, face.leftEyeTransform.columns.3.z)
        let rightEye = SIMD3(face.rightEyeTransform.columns.3.x, face.rightEyeTransform.columns.3.y, face.rightEyeTransform.columns.3.z)
        let l = frame.camera.projectPoint(world(leftEye), orientation: .portrait, viewportSize: viewport)
        let r = frame.camera.projectPoint(world(rightEye), orientation: .portrait, viewportSize: viewport)
        var roll = Float(atan2(l.y - r.y, l.x - r.x) * 180 / .pi)
        if roll > 90 { roll -= 180 } else if roll < -90 { roll += 180 }
        let shapes = face.blendShapes
        func shape(_ key: ARFaceAnchor.BlendShapeLocation) -> Float { shapes[key]?.floatValue ?? 0 }
        return FaceScan(samples: samples,
                        yaw: tilt * Float(d.dx / length), pitch: tilt * Float(d.dy / length), roll: roll,
                        blink: max(shape(.eyeBlinkLeft), shape(.eyeBlinkRight)),
                        smile: max(shape(.mouthSmileLeft), shape(.mouthSmileRight)),
                        jawOpen: shape(.jawOpen), browRaise: max(shape(.browInnerUp), shape(.browOuterUpLeft), shape(.browOuterUpRight)),
                        ipd: simd_distance(leftEye, rightEye) * 1000, eyeY: (leftEye.y + rightEye.y) * 500,
                        outline: outline, viewport: viewport)
    }
}

/// Reads the ARKit camera picture (YCbCr) the way the makeup shader does: same matrix, range and tone curve.
struct CameraPixels {
    let buffer: CVPixelBuffer
    let bt709: Bool, full: Bool

    init?(_ buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        self.buffer = buffer
        let matrix = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        bt709 = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
        full = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }

    func lock() { CVPixelBufferLockBaseAddress(buffer, .readOnly) }
    func unlock() { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    /// Mean of a 3 x 3 pixel block (less sensor noise), as Lab. Call between `lock()` and `unlock()`.
    func lab(at point: CGPoint) -> Lab? {
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 1, y >= 1, x < w - 1, y < h - 1,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), cRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let yp = yBase.assumingMemoryBound(to: UInt8.self), cp = cBase.assumingMemoryBound(to: UInt8.self)
        var luma: Float = 0
        for dy in -1...1 { for dx in -1...1 { luma += Float(yp[(y + dy) * yRow + x + dx]) } }
        let ci = (y / 2) * cRow + (x / 2) * 2
        var l = luma / 9 / 255
        var cb = Float(cp[ci]) / 255 - 0.5, cr = Float(cp[ci + 1]) / 255 - 0.5
        if !full { l = (l - 16 / 255) * 255 / 219; cb *= 255 / 224; cr *= 255 / 224 }
        let rgb = bt709 ? SIMD3(l + 1.5748 * cr, l - 0.187324 * cb - 0.468124 * cr, l + 1.8556 * cb)
                        : SIMD3(l + 1.402 * cr, l - 0.344136 * cb - 0.714136 * cr, l + 1.772 * cb)
        let linear = SIMD3(BeautyBlushConfiguration.cameraLinear(min(max(rgb.x, 0), 1)),
                           BeautyBlushConfiguration.cameraLinear(min(max(rgb.y, 0), 1)),
                           BeautyBlushConfiguration.cameraLinear(min(max(rgb.z, 0), 1)))
        return FeedbackColor.lab(linear: linear)
    }
}

/// The makeup layer's picture as shown (sRGB-encoded BGRA, the drawable's pixels), read back at the shutter.
struct ScreenPixels: @unchecked Sendable {
    let width: Int, height: Int, bytesPerRow: Int
    let bytes: [UInt8]

    func lab(atViewPoint point: CGPoint, viewport: CGSize) -> Lab? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        let x = Int(point.x / viewport.width * CGFloat(width)), y = Int(point.y / viewport.height * CGFloat(height))
        guard x >= 1, y >= 1, x < width - 1, y < height - 1 else { return nil }
        var sum = SIMD3<Float>.zero
        for dy in -1...1 {
            for dx in -1...1 {
                let i = (y + dy) * bytesPerRow + (x + dx) * 4
                sum += SIMD3(BeautyBlushConfiguration.linear(Float(bytes[i + 2]) / 255),
                             BeautyBlushConfiguration.linear(Float(bytes[i + 1]) / 255),
                             BeautyBlushConfiguration.linear(Float(bytes[i]) / 255))
            }
        }
        return FeedbackColor.lab(linear: sum / 9)
    }

    /// The picture as an image, for the photo the person sees.
    func image(scale: CGFloat) -> UIImage? {
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                               space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
}

/// Colour maths for the feedback (D65, sRGB primaries).
enum FeedbackColor {
    static func lab(linear c: SIMD3<Float>) -> Lab {
        let x = (0.4124 * c.x + 0.3576 * c.y + 0.1805 * c.z) / 0.95047
        let y = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
        let z = (0.0193 * c.x + 0.1192 * c.y + 0.9505 * c.z) / 1.08883
        func f(_ t: Float) -> Float { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        return Lab(116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func lab(sRGB r: Double, _ g: Double, _ b: Double) -> Lab {
        lab(linear: SIMD3(BeautyBlushConfiguration.linear(Float(r)), BeautyBlushConfiguration.linear(Float(g)),
                          BeautyBlushConfiguration.linear(Float(b))))
    }

    static func chroma(_ c: Lab) -> Float { hypot(c.y, c.z) }

    /// Hue angle in degrees, 0...360.
    static func hue(a: Float, b: Float) -> Float {
        let h = atan2(b, a) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    /// Signed smallest difference a - b between two hue angles, degrees.
    static func hueDifference(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// CIEDE2000 colour difference.
    static func deltaE2000(_ p: Lab, _ q: Lab) -> Float {
        let (l1, a1, b1) = (Double(p.x), Double(p.y), Double(p.z)), (l2, a2, b2) = (Double(q.x), Double(q.y), Double(q.z))
        let c1 = hypot(a1, b1), c2 = hypot(a2, b2), cm = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cm, 7) / (pow(cm, 7) + pow(25, 7))))
        let ap1 = (1 + g) * a1, ap2 = (1 + g) * a2
        let cp1 = hypot(ap1, b1), cp2 = hypot(ap2, b2)
        func angle(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) * 180 / .pi
            return h < 0 ? h + 360 : h
        }
        let hp1 = angle(b1, ap1), hp2 = angle(b2, ap2)
        let dl = l2 - l1, dc = cp2 - cp1
        var dh = 0.0
        if cp1 * cp2 != 0 {
            dh = hp2 - hp1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        }
        let dH = 2 * sqrt(cp1 * cp2) * sin(dh * .pi / 360)
        let lm = (l1 + l2) / 2, cpm = (cp1 + cp2) / 2
        var hm = hp1 + hp2
        if cp1 * cp2 != 0 {
            if abs(hp1 - hp2) <= 180 { hm /= 2 } else { hm = hm < 360 ? (hm + 360) / 2 : (hm - 360) / 2 }
        }
        let t = 1 - 0.17 * cos((hm - 30) * .pi / 180) + 0.24 * cos(2 * hm * .pi / 180)
            + 0.32 * cos((3 * hm + 6) * .pi / 180) - 0.20 * cos((4 * hm - 63) * .pi / 180)
        let dTheta = 30 * exp(-pow((hm - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cpm, 7) / (pow(cpm, 7) + pow(25, 7)))
        let sl = 1 + 0.015 * pow(lm - 50, 2) / sqrt(20 + pow(lm - 50, 2))
        let sc = 1 + 0.045 * cpm, sh = 1 + 0.015 * cpm * t
        let rt = -sin(2 * dTheta * .pi / 180) * rc
        return Float(sqrt(pow(dl / sl, 2) + pow(dc / sc, 2) + pow(dH / sh, 2) + rt * (dc / sc) * (dH / sh)))
    }
}
