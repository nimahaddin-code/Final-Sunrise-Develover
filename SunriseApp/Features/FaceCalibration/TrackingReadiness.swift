// -Nimah: TrackingReadiness.swift — implementasi MVP SunriseApp.
import Foundation

struct TrackingReadiness {
    private var since: TimeInterval?
    private var lastTimestamp: TimeInterval?
    mutating func update(timestamp: TimeInterval, tracked: Bool, steady: Bool) -> Bool {
        // -Nimah: Gap/loss/movement memulai kalibrasi ulang, tidak menjumlah frame terpisah.
        let contiguous = lastTimestamp.map { timestamp > $0 && timestamp - $0 < 0.5 } ?? false
        lastTimestamp = timestamp
        guard tracked && steady else { since = nil; return false }
        if !contiguous || since == nil { since = timestamp }
        return timestamp - (since ?? timestamp) >= 2
    }
    mutating func reset() { since = nil; lastTimestamp = nil }
}
