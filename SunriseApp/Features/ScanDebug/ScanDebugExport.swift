import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    /// The file the Scan Debug tab shares with the Mac editor. Declared in `Info.plist` (exported type) in both apps.
    static let sunriseScan = UTType(exportedAs: "com.sunrise.scan-debug", conformingTo: .json)
}

/// One scan on its way to the Mac editor: the scan picture (JPEG, inside the file), the raw points the scanner drew, and the
/// corrected points so far. A single JSON file, so AirDrop and Files treat it as any other document.
///
/// This is the one place a scan picture leaves memory. It happens only when the person taps "Export for Mac", and the system
/// share sheet decides where the file goes (see `AGENTS.md`). The Mac app compiles this same file.
struct ScanDebugExportFile: Codable, Equatable, Sendable {
    static let formatName = "sunrise-scan-debug"
    static let currentVersion = 1
    static let fileExtension = "sunrisescan"

    /// `pointsOnly`: a saved `.raw.json` / `.corrected.json` file, which has the points but not the picture.
    enum Failure: Error, Equatable { case notAScanFile, pointsOnly, newerVersion(Int), unreadablePicture }

    var format = Self.formatName
    var version = Self.currentVersion
    var name: String
    var kind: ScanDebugKind
    var exportedAt: Date
    var imageWidth: Int
    var imageHeight: Int
    /// The scan picture, JPEG; JSON stores it as base64.
    var imageJPEG: Data
    var raw: [ScanDebugPoint]
    /// The corrected points when exported; the same as `raw` when nothing was moved yet.
    var corrected: [ScanDebugPoint]
    var measurements: [String: Double]
    var classification: String?

    init(name: String, raw: ScanDebugPointSet, corrected: ScanDebugPointSet, picture: CGImage, exportedAt: Date = Date()) throws {
        guard let jpeg = Self.jpeg(from: picture) else { throw Failure.unreadablePicture }
        self.name = name
        kind = raw.kind
        self.exportedAt = exportedAt
        imageWidth = picture.width
        imageHeight = picture.height
        imageJPEG = jpeg
        self.raw = raw.points
        self.corrected = corrected.points
        // Measured at the picture's own size, which is what the points are normalized to.
        let report = ScanDebugMeasure.report(for: ScanDebugPointSet(kind: raw.kind, imageWidth: picture.width, imageHeight: picture.height, points: raw.points))
        measurements = Dictionary(uniqueKeysWithValues: report.metrics.map { ($0.key, $0.value) })
        classification = report.classification
    }

    var rawSet: ScanDebugPointSet { ScanDebugPointSet(kind: kind, imageWidth: imageWidth, imageHeight: imageHeight, points: raw) }
    var correctedSet: ScanDebugPointSet { ScanDebugPointSet(kind: kind, imageWidth: imageWidth, imageHeight: imageHeight, points: corrected) }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ScanDebugExportFile {
        struct Header: Decodable { var format: String; var version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == formatName else {
            let recordDecoder = JSONDecoder()
            recordDecoder.dateDecodingStrategy = .iso8601
            throw (try? recordDecoder.decode(ScanDebugRecord.self, from: data)) != nil ? Failure.pointsOnly : Failure.notAScanFile
        }
        guard header.version <= currentVersion else { throw Failure.newerVersion(header.version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScanDebugExportFile.self, from: data)
    }

    /// The picture decoded from `imageJPEG`.
    func picture() -> CGImage? {
        CGImageSourceCreateWithData(imageJPEG as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    static func jpeg(from image: CGImage, quality: Double = 0.92) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
