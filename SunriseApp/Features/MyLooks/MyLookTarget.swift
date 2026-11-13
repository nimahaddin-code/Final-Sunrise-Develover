// -Nimah: the try-on's measured target (the desired photo's `FaceScan`) as a small file, so "Try again" from My Looks can
// score a new result without a new desired photo. Numbers only (mesh positions in face millimetres, colours, screen
// points), packed as floats and compressed; saved in the look's folder with the same protection as its photos and deleted
// with it. The user chose this on 2026-11-13.
import CoreGraphics
import Foundation

enum MyLookTarget {
    static let fileName = "target.scan"
    /// Floats per sample: position 3, area 1, lab 3, rendered 3 (NaN when not read), screen 2, visible 1.
    private static let stride = 13

    private struct Archive: Codable {
        var version = 1
        var count: Int
        var samples: Data
        var yaw: Float, pitch: Float, roll: Float
        var blink: Float, smile: Float, jawOpen: Float, browRaise: Float
        var ipd: Float, eyeY: Float
        var viewport: CGSize
        var leftEye: CGPoint?, rightEye: CGPoint?
        var cheeks: [Cheek]?
    }

    private struct Cheek: Codable {
        var inner: [CGPoint], outer: [CGPoint], center: CGPoint, outward: CGPoint
    }

    static func encode(_ scan: FaceScan) throws -> Data {
        var floats = [Float]()
        floats.reserveCapacity(scan.samples.count * stride)
        for s in scan.samples {
            floats += [s.position.x, s.position.y, s.position.z, s.area, s.lab.x, s.lab.y, s.lab.z]
            floats += s.rendered.map { [$0.x, $0.y, $0.z] } ?? [.nan, .nan, .nan]
            floats += [Float(s.screen.x), Float(s.screen.y), s.visible ? 1 : 0]
        }
        let packed = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let archive = Archive(count: scan.samples.count, samples: packed, yaw: scan.yaw, pitch: scan.pitch, roll: scan.roll,
                              blink: scan.blink, smile: scan.smile, jawOpen: scan.jawOpen, browRaise: scan.browRaise,
                              ipd: scan.ipd, eyeY: scan.eyeY, viewport: scan.viewport, leftEye: scan.leftEye, rightEye: scan.rightEye,
                              cheeks: scan.outline?.cheeks.map { Cheek(inner: $0.inner, outer: $0.outer, center: $0.center, outward: $0.outward) })
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try (encoder.encode(archive) as NSData).compressed(using: .lzfse) as Data
    }

    static func decode(_ data: Data) throws -> FaceScan {
        let raw = try (data as NSData).decompressed(using: .lzfse) as Data
        let a = try PropertyListDecoder().decode(Archive.self, from: raw)
        guard a.samples.count == a.count * stride * MemoryLayout<Float>.size else { throw CocoaError(.fileReadCorruptFile) }
        let floats = a.samples.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var samples: [FaceScan.Sample] = []
        samples.reserveCapacity(a.count)
        for i in 0..<a.count {
            let f = floats[(i * stride)..<((i + 1) * stride)].map { $0 }
            let rendered: Lab? = f[7].isNaN ? nil : Lab(f[7], f[8], f[9])
            samples.append(FaceScan.Sample(position: SIMD3(f[0], f[1], f[2]), area: f[3], lab: Lab(f[4], f[5], f[6]),
                                           rendered: rendered, screen: CGPoint(x: CGFloat(f[10]), y: CGFloat(f[11])),
                                           visible: f[12] > 0.5))
        }
        let outline = a.cheeks.map { cheeks in
            BlushGuideSnapshot(cheeks: cheeks.map { .init(inner: $0.inner, outer: $0.outer, center: $0.center, outward: $0.outward) })
        }
        return FaceScan(samples: samples, yaw: a.yaw, pitch: a.pitch, roll: a.roll, blink: a.blink, smile: a.smile,
                        jawOpen: a.jawOpen, browRaise: a.browRaise, ipd: a.ipd, eyeY: a.eyeY, outline: outline,
                        viewport: a.viewport, leftEye: a.leftEye, rightEye: a.rightEye)
    }
}
