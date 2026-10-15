// -Nimah: BlushMask.swift — implementasi MVP SunriseApp.
import Foundation

// -Nimah: Bobot vertex neutral face-local; mesh yang berubah membawa mask saat ekspresi berubah.
enum BlushMask {
    static func weight(x: Float, y: Float, z: Float) -> Float {
        guard z > 0.015 else { return 0 }
        let dx = (abs(x) - 0.043) / 0.025
        let dy = (y + 0.026) / 0.018
        return max(0, 1 - dx * dx - dy * dy) * 0.60
    }
}
