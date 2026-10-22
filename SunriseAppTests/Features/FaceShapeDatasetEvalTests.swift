import Foundation
import ImageIO
import XCTest
@testable import SunriseApp

/// Accuracy of the photo path on a labelled face shape dataset (folders named after shapes, e.g. Heart/, Long/).
/// Skipped unless `FACE_SHAPE_DATASET` is set. xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the
/// simulator, so run it as `TEST_RUNNER_FACE_SHAPE_DATASET=/path/to/dataset xcodebuild test ...`.
/// Writes `report.txt` and `results.csv` to `FACE_SHAPE_EVAL_OUTPUT` (default: the runner's temporary directory).
final class FaceShapeDatasetEvalTests: XCTestCase {
    func testDatasetAccuracy() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FACE_SHAPE_DATASET"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FACE_SHAPE_DATASET to a labelled face shape dataset folder.")
        }
        let samples = FaceShapeDataset.samples(in: URL(fileURLWithPath: path, isDirectory: true))
        XCTAssertFalse(samples.isEmpty, "No labelled images under \(path)")
        guard !samples.isEmpty else { return }

        let measured = await FaceShapeDataset.measure(samples)
        let evaluation = FaceShapeEvaluation(measured: measured)

        let output = URL(fileURLWithPath: environment["FACE_SHAPE_EVAL_OUTPUT"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("face-shape-eval", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try evaluation.report.write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        try evaluation.csv.write(to: output.appendingPathComponent("results.csv"), atomically: true, encoding: .utf8)
        print(evaluation.report)
        print("Face shape eval written to \(output.path)")
        add(XCTAttachment(string: evaluation.report))
    }
}

final class FaceShapeCalibrationTests: XCTestCase {
    func testFitRecoversClassMeansAsPrototypes() throws {
        let means: [FaceShape: FaceProportions] = [
            .oval: FaceProportions(length: 1.30, forehead: 0.80, jaw: 0.78, chin: 0.45),
            .round: FaceProportions(length: 1.15, forehead: 0.80, jaw: 0.82, chin: 0.45),
            .oblong: FaceProportions(length: 1.45, forehead: 0.82, jaw: 0.80, chin: 0.46),
        ]
        let jitter: [Float] = [-0.01, 0, 0.01]
        let labelled = means.flatMap { shape, mean in
            jitter.map { (shape, FaceProportions(length: mean.length + $0, forehead: mean.forehead,
                                                 jaw: mean.jaw - $0, chin: mean.chin)) }
        }
        let fit = try XCTUnwrap(FaceShapeCalibration.fit(labelled))
        XCTAssertEqual(fit.reference.length, (1.30 + 1.15 + 1.45) / 3, accuracy: 1e-4)
        XCTAssertEqual(fit.prototypes[.diamond], FaceShapeClassifier.prototypes[.diamond])

        let classifier = fit.classifier
        for (shape, mean) in means {
            XCTAssertEqual(classifier.classify(mean).shape, shape)
        }
    }
}

struct FaceShapeSample: Sendable {
    let url: URL
    let path: String
    let label: FaceShape
    let isHoldout: Bool
}

enum FaceShapeDataset {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "bmp", "gif", "tif", "tiff"]
    /// Longest side fed to Vision; dataset photos range from thumbnails to 4K.
    static let maxPixelSize = 1600

    static func label(forFolder name: String) -> FaceShape? {
        let name = name.lowercased()
        return name == "long" ? .oblong : FaceShape(rawValue: name)
    }

    /// Labels come from the parent folder. Images under a `test`/`valid` folder are held out for evaluation;
    /// if there are none, every fifth image is.
    static func samples(in root: URL) -> [FaceShapeSample] {
        let root = root.standardizedFileURL
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: [(URL, String, FaceShape)] = []
        for case let url as URL in files where imageExtensions.contains(url.pathExtension.lowercased()) {
            guard let label = label(forFolder: url.deletingLastPathComponent().lastPathComponent) else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(root.path.count)).trimmingCharacters(in: ["/"])
            found.append((url, path, label))
        }
        found.sort { $0.1 < $1.1 }
        func isSplitHoldout(_ path: String) -> Bool {
            path.lowercased().split(separator: "/").dropLast().contains { $0.contains("test") || $0.hasPrefix("val") }
        }
        let hasSplit = found.contains { isSplitHoldout($0.1) }
        return found.enumerated().map { index, item in
            FaceShapeSample(url: item.0, path: item.1, label: item.2,
                            isHoldout: hasSplit ? isSplitHoldout(item.1) : index % 5 == 4)
        }
    }

    static func measure(_ sample: FaceShapeSample) -> Result<FaceProportions, MeasureFailure> {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sample.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return .failure(.unreadable) }
        return PhotoFaceMeasurer.proportions(of: image).mapError(MeasureFailure.photo)
    }

    /// Measures every sample, one Vision request per core at a time.
    static func measure(_ samples: [FaceShapeSample]) async -> [(FaceShapeSample, Result<FaceProportions, MeasureFailure>)] {
        await withTaskGroup(of: (Int, Result<FaceProportions, MeasureFailure>).self) { group in
            var results = [Result<FaceProportions, MeasureFailure>](repeating: .failure(.unreadable), count: samples.count)
            var next = 0
            for _ in 0..<min(ProcessInfo.processInfo.activeProcessorCount, samples.count) {
                let index = next
                next += 1
                group.addTask { (index, measure(samples[index])) }
            }
            for await (index, result) in group {
                results[index] = result
                guard next < samples.count else { continue }
                let index = next
                next += 1
                group.addTask { (index, measure(samples[index])) }
            }
            return Array(zip(samples, results))
        }
    }

    enum MeasureFailure: Error, CustomStringConvertible {
        case unreadable
        case photo(PhotoFaceMeasurer.Failure)

        var description: String {
            switch self {
            case .unreadable: "unreadable"
            case .photo(.visionFailed): "vision_failed"
            case .photo(.noFace): "no_face"
            case .photo(.turnedAway): "turned_away"
            case .photo(.unmeasurable): "unmeasurable"
            }
        }
    }
}

/// Fits the photo classifier to labelled proportions: the reference is the mean of the class means, and each
/// labelled class's prototype is its mean deviation from that reference. Shapes without samples keep their prototype.
/// `unit` is chosen so the fitted prototypes have the same overall size as the current ones.
struct FaceShapeCalibration {
    let classMeans: [FaceShape: FaceProportions]
    let reference: FaceProportions
    let unit: Float
    let prototypes: [FaceShape: SIMD4<Float>]

    var classifier: FaceShapeClassifier {
        FaceShapeClassifier(reference: reference, unit: unit, prototypes: prototypes)
    }

    static func fit(_ labelled: [(FaceShape, FaceProportions)]) -> FaceShapeCalibration? {
        let grouped = Dictionary(grouping: labelled) { $0.0 }.mapValues { $0.map { vector($0.1) } }
        let classMeans = grouped.mapValues { $0.reduce(.zero, +) / Float($0.count) }
        guard !classMeans.isEmpty else { return nil }
        let reference = classMeans.values.reduce(.zero, +) / Float(classMeans.count)
        let deviations = classMeans.mapValues { $0 / reference - 1 }

        func rms(_ vectors: [SIMD4<Float>]) -> Float {
            (vectors.map { ($0 * $0).sum() }.reduce(0, +) / Float(max(1, vectors.count))).squareRoot()
        }
        let current = deviations.keys.compactMap { FaceShapeClassifier.prototypes[$0] }
        let size = rms(Array(deviations.values))
        let unit = max(size, 1e-4) / max(rms(current), 1e-3)
        var prototypes = FaceShapeClassifier.prototypes
        for (shape, deviation) in deviations {
            prototypes[shape] = ((deviation / unit) * 100).rounded(.toNearestOrEven) / 100
        }
        return FaceShapeCalibration(classMeans: classMeans.mapValues(proportions), reference: proportions(reference),
                                    unit: unit, prototypes: prototypes)
    }

    /// Unit that maximises accuracy with the current prototypes, for comparing "reference only" against a full refit.
    static func bestUnit(reference: FaceProportions, for labelled: [(FaceShape, FaceProportions)]) -> Float {
        stride(from: Float(0.01), through: 0.2, by: 0.005).max { a, b in
            accuracy(FaceShapeClassifier(reference: reference, unit: a), labelled)
                < accuracy(FaceShapeClassifier(reference: reference, unit: b), labelled)
        } ?? 0.04
    }

    static func accuracy(_ classifier: FaceShapeClassifier, _ labelled: [(FaceShape, FaceProportions)]) -> Double {
        guard !labelled.isEmpty else { return 0 }
        return Double(labelled.filter { classifier.classify($0.1).shape == $0.0 }.count) / Double(labelled.count)
    }

    static func vector(_ p: FaceProportions) -> SIMD4<Float> { SIMD4(p.length, p.forehead, p.jaw, p.chin) }
    static func proportions(_ v: SIMD4<Float>) -> FaceProportions {
        FaceProportions(length: v[0], forehead: v[1], jaw: v[2], chin: v[3])
    }
}

struct FaceShapeEvaluation {
    let report: String
    let csv: String

    init(measured: [(FaceShapeSample, Result<FaceProportions, FaceShapeDataset.MeasureFailure>)]) {
        let succeeded = measured.compactMap { sample, result in (try? result.get()).map { (sample, $0) } }
        let train = succeeded.filter { !$0.0.isHoldout }.map { ($0.0.label, $0.1) }
        let holdout = succeeded.filter { $0.0.isHoldout }.map { ($0.0.label, $0.1) }
        let fit = FaceShapeCalibration.fit(train)

        var configurations: [(name: String, classifier: FaceShapeClassifier)] = [("Current photo classifier", .photo)]
        if let fit {
            let unit = FaceShapeCalibration.bestUnit(reference: fit.reference, for: train)
            configurations.append(("Fitted reference, current prototypes (unit \(Self.format(unit)))",
                                   FaceShapeClassifier(reference: fit.reference, unit: unit)))
            configurations.append(("Fitted reference and prototypes", fit.classifier))
        }

        let labels = FaceShape.allCases.filter { shape in measured.contains { $0.0.label == shape } }
        let missing = FaceShape.allCases.filter { !labels.contains($0) }
        var lines = ["Face shape photo eval", ""]
        lines.append("Images: \(measured.count) (train \(measured.filter { !$0.0.isHoldout }.count), "
                     + "holdout \(measured.filter { $0.0.isHoldout }.count))")
        let failures = Dictionary(grouping: measured.compactMap { _, result -> String? in
            if case .failure(let failure) = result { failure.description } else { nil }
        }, by: { $0 }).mapValues(\.count)
        lines.append("Failed detections: \(failures.values.reduce(0, +)) "
                     + failures.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        lines.append("Classes with samples: \(labels.map(\.rawValue).joined(separator: ", "))")
        if !missing.isEmpty {
            lines.append("No samples (accuracy not measured, still predictable): \(missing.map(\.rawValue).joined(separator: ", "))")
        }

        for configuration in configurations {
            for (split, set) in [("holdout", holdout), ("train", train)] where !set.isEmpty {
                lines.append("")
                lines.append("## \(configuration.name) — \(split)")
                lines += Self.confusion(classifier: configuration.classifier, set: set, labels: labels)
            }
        }

        if let fit {
            lines.append("")
            lines.append("## Class mean proportions (train)")
            lines.append(Self.row(["class", "length", "forehead", "jaw", "chin"]))
            for shape in labels {
                guard let mean = fit.classMeans[shape] else { continue }
                lines.append(Self.row([shape.rawValue] + [mean.length, mean.forehead, mean.jaw, mean.chin].map(Self.format)))
            }
            let r = fit.reference
            lines.append("")
            lines.append("## Suggested photo constants")
            lines.append("static let reference = FaceProportions(length: \(Self.format(r.length)), forehead: \(Self.format(r.forehead)), "
                         + "jaw: \(Self.format(r.jaw)), chin: \(Self.format(r.chin)))")
            lines.append("static let unit: Float = \(Self.format(fit.unit))")
            lines.append("prototypes (length, forehead, jaw, chin):")
            for shape in FaceShape.allCases {
                let p = fit.prototypes[shape] ?? .zero, old = FaceShapeClassifier.prototypes[shape] ?? .zero
                let note = fit.classMeans[shape] == nil ? "  (no samples, unchanged)" : "  (was \(Self.vector(old)))"
                lines.append("    .\(shape.rawValue): \(Self.vector(p)),\(note)")
            }
        }
        report = lines.joined(separator: "\n")

        let classifiers = configurations.map(\.classifier)
        var rows = ["path,split,label,status,length,forehead,jaw,chin,"
                    + (0..<classifiers.count).map { "predicted_\($0 + 1)" }.joined(separator: ",") + ",confidence_last"]
        for (sample, result) in measured {
            var row = ["\"\(sample.path.replacingOccurrences(of: "\"", with: "\"\""))\"", sample.isHoldout ? "holdout" : "train",
                       sample.label.rawValue]
            switch result {
            case .success(let p):
                let results = classifiers.map { $0.classify(p) }
                row += ["ok"] + [p.length, p.forehead, p.jaw, p.chin].map(Self.format) + results.map(\.shape.rawValue)
                row.append(Self.format(Float(results.last?.confidence ?? 0)))
            case .failure(let failure):
                row += [failure.description] + Array(repeating: "", count: 5 + classifiers.count)
            }
            rows.append(row.joined(separator: ","))
        }
        csv = rows.joined(separator: "\n") + "\n"
    }

    private static func confusion(classifier: FaceShapeClassifier, set: [(FaceShape, FaceProportions)],
                                  labels: [FaceShape]) -> [String] {
        var counts: [FaceShape: [FaceShape: Int]] = [:]
        for (label, proportions) in set {
            counts[label, default: [:]][classifier.classify(proportions).shape, default: 0] += 1
        }
        let correct = labels.reduce(0) { $0 + (counts[$1]?[$1] ?? 0) }
        var lines = ["Overall accuracy: \(percent(correct, set.count)) (\(correct)/\(set.count))",
                     row(["actual \\ predicted"] + FaceShape.allCases.map(\.rawValue) + ["accuracy"])]
        for label in labels {
            let row = counts[label] ?? [:], total = row.values.reduce(0, +)
            lines.append(self.row([label.rawValue] + FaceShape.allCases.map { "\(row[$0] ?? 0)" }
                                  + [percent(row[label] ?? 0, total)]))
        }
        return lines
    }

    private static func row(_ cells: [String]) -> String {
        cells.enumerated().map { $0.offset == 0 ? $0.element.padding(toLength: 20, withPad: " ", startingAt: 0)
                                                : $0.element.leftPadded(to: 9) }.joined()
    }

    private static func percent(_ part: Int, _ total: Int) -> String {
        total == 0 ? "-" : String(format: "%.1f%%", 100 * Double(part) / Double(total))
    }

    static func format(_ value: Float) -> String { String(format: "%.3f", value) }

    private static func vector(_ v: SIMD4<Float>) -> String {
        "SIMD4(\((0..<4).map { String(format: "%.2f", v[$0]) }.joined(separator: ", ")))"
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? " " + self : String(repeating: " ", count: length - count) + self
    }
}
