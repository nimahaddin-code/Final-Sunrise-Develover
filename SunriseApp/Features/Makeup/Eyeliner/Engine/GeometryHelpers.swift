// Ported from the EyelinerSpike (MediaPipe + 2D overlay approach, see Docs/Decisions/0002-mediapipe-eyeliner.md).
import CoreGraphics

// MARK: - CGPoint vector math (pure, no UI)

extension CGPoint {
    static func + (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: l.x * s, y: l.y * s) }
    static prefix func - (p: CGPoint) -> CGPoint { CGPoint(x: -p.x, y: -p.y) }

    var length: CGFloat { hypot(x, y) }

    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }

    /// Unit vector; falls back to (1, 0) for a zero vector.
    func normalized() -> CGPoint {
        let l = length
        return l > 1e-9 ? CGPoint(x: x / l, y: y / l) : CGPoint(x: 1, y: 0)
    }

    func lerp(to o: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (o.x - x) * t, y: y + (o.y - y) * t)
    }
}

@inline(__always)
func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

func signedArea(_ pts: [CGPoint]) -> CGFloat {
    guard pts.count >= 3 else { return 0 }
    var a: CGFloat = 0
    for i in pts.indices {
        let p = pts[i]
        let q = pts[(i + 1) % pts.count]
        a += p.x * q.y - q.x * p.y
    }
    return a / 2
}
