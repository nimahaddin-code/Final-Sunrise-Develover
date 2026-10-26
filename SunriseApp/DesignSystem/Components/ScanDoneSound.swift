import AVFoundation

/// The short "done" sound played when a scan finishes.
///
/// Order of preference: a licensed `scan_done.caf` / `scan_done.wav` added to the app, then the system's `payment_success.caf`,
/// then an original two-note bell made in code (`wav()`). The system file is not a documented API: iOS may rename or remove it, which
/// is why the bell stays as the fallback. It uses the ambient audio category: it follows the silent switch and does not stop music.
enum ScanDoneSound {
    private static let sampleRate = 44_100
    /// In the Simulator, the iOS system files live under `SIMULATOR_ROOT`; on a device that variable is absent.
    static let systemSoundURL = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["SIMULATOR_ROOT"] ?? "")
                                    + "/System/Library/Audio/UISounds/payment_success.caf")
    @MainActor private static var player: AVAudioPlayer?

    @MainActor static func play() {
        let bundled = ["caf", "wav"].lazy.compactMap { Bundle.main.url(forResource: "scan_done", withExtension: $0) }.first
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let file = [bundled, systemSoundURL].lazy.compactMap { $0 }.compactMap { try? AVAudioPlayer(contentsOf: $0) }.first
        guard let player = file ?? (try? AVAudioPlayer(data: wav())) else { return }
        player.volume = 0.8
        player.prepareToPlay()
        player.play()
        Self.player = player
    }

    /// A 16-bit mono WAV file: a bright bell note, then a fifth above it, each with a few fading overtones.
    static func wav() -> Data {
        let notes: [(start: Double, frequency: Double, decay: Double)] = [(0, 1318.5, 0.14), (0.11, 1975.5, 0.22)]
        let duration = 1.0
        let count = Int(duration * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            var value = 0.0
            for note in notes where time >= note.start {
                let age = time - note.start
                let envelope = min(1, age / 0.004) * exp(-age / note.decay)   // quick attack, then a fade
                for (partial, weight) in [(1.0, 1.0), (2.0, 0.35), (3.01, 0.12)] {
                    value += weight * envelope * sin(2 * .pi * note.frequency * partial * age)
                }
            }
            // A short fade at the very end, so the file never stops mid-wave with a click.
            let fade = min(1, (duration - time) / 0.05)
            samples[index] = Int16(max(-1, min(1, value * 0.3 * fade)) * Double(Int16.max))
        }
        return header(byteCount: count * 2) + samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func header(byteCount: Int) -> Data {
        func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        func le16(_ value: Int) -> [UInt8] { (0..<2).map { UInt8((value >> (8 * $0)) & 0xFF) } }
        var bytes = Array("RIFF".utf8) + le32(36 + byteCount) + Array("WAVEfmt ".utf8) + le32(16) + le16(1) + le16(1)
        bytes += le32(sampleRate) + le32(sampleRate * 2) + le16(2) + le16(16) + Array("data".utf8) + le32(byteCount)
        return Data(bytes)
    }
}
