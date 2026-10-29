import CoreML
import Foundation

/// MI-GAN inpainting (Picsart AI Research, MIT-licensed code and weights) for hiding the natural brow, run with Core ML
/// on an upright 256 x 256 face crop. Optional: without the bundled model the push-pull fill is used on its own.
/// See Docs/Decisions/0014-brow-inpainting.md for where the model comes from and how it is converted.
final class BrowInpainter: @unchecked Sendable {
    static let modelName = "MIGANFace256"
    static let side = 256
    private let model: MLModel?
    private let inputName: String
    private let outputName: String

    init(bundle: Bundle = .main) {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = bundle.url(forResource: Self.modelName, withExtension: "mlmodelc")
            .flatMap { try? MLModel(contentsOf: $0, configuration: configuration) }
        model = loaded
        inputName = loaded?.modelDescription.inputDescriptionsByName.keys.sorted().first ?? "input"
        outputName = loaded?.modelDescription.outputDescriptionsByName.keys.sorted().first ?? "output"
    }

    var isAvailable: Bool { model != nil }

    /// `rgba`: the face crop, sRGB bytes. `hole`: 255 where the brow is to be filled. Returns the inpainted crop as RGBA
    /// bytes, known pixels unchanged. Blocking; call it off the render queue.
    func inpaint(rgba: [UInt8], hole: [UInt8]) throws -> [UInt8] {
        guard let model else { throw CocoaError(.featureUnsupported) }
        let input = try Self.input(rgba: rgba, hole: hole)
        let features = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
        guard let output = try model.prediction(from: features).featureValue(for: outputName)?.multiArrayValue else {
            throw CocoaError(.coderValueNotFound)
        }
        return Self.output(output, rgba: rgba, hole: hole)
    }

    /// MI-GAN's generator input, 1 x 4 x 256 x 256: the mask minus 0.5, then the image (in -1...1) times the mask,
    /// where the mask is 1 to keep and 0 to fill.
    static func input(rgba: [UInt8], hole: [UInt8]) throws -> MLMultiArray {
        let n = side * side
        guard rgba.count == n * 4, hole.count == n else { throw CocoaError(.coderInvalidValue) }
        let array = try MLMultiArray(shape: [1, 4, NSNumber(value: side), NSNumber(value: side)], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: n * 4)
        for i in 0..<n {
            let keep: Float = hole[i] > 127 ? 0 : 1
            pointer[i] = keep - 0.5
            for c in 0..<3 { pointer[(c + 1) * n + i] = (Float(rgba[i * 4 + c]) / 127.5 - 1) * keep }
        }
        return array
    }

    /// The generator's 1 x 3 x 256 x 256 output (-1...1) where the mask fills, the original bytes elsewhere.
    static func output(_ array: MLMultiArray, rgba: [UInt8], hole: [UInt8]) -> [UInt8] {
        let n = side * side
        var out = rgba
        guard array.count >= n * 3 else { return out }
        func value(_ index: Int) -> Float {
            switch array.dataType {
            case .float16: return Float(array.dataPointer.bindMemory(to: Float16.self, capacity: n * 3)[index])
            case .double: return Float(array.dataPointer.bindMemory(to: Double.self, capacity: n * 3)[index])
            default: return array.dataPointer.bindMemory(to: Float.self, capacity: n * 3)[index]
            }
        }
        for i in 0..<n where hole[i] > 127 {
            for c in 0..<3 { out[i * 4 + c] = UInt8(max(0, min(255, ((value(c * n + i) + 1) * 127.5).rounded()))) }
        }
        return out
    }
}
