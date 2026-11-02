// -Nimah: SavedLooksStoring.swift — implementasi MVP SunriseApp.
import Foundation

enum SavedLooksError: Error, Equatable, LocalizedError {
    case notImplemented, invalidCapture, invalidIdentifier, missingCapture
    var errorDescription: String? {
        switch self {
        case .notImplemented: return "This storage operation is not available."
        case .invalidCapture: return "Both camera photos are required and must be smaller than 15 MB each."
        case .invalidIdentifier: return "This saved look identifier is invalid."
        case .missingCapture: return "A saved photo is missing. Please try another look."
        }
    }
}
protocol SavedLooksStoring: Sendable {
    func list() async throws -> [SavedLookMetadata]
    func save(_ look: SavedLookMetadata) async throws
    func save(referenceID: String, before: Data, after: Data) async throws -> SavedLookMetadata
    func imageData(for lookID: String, kind: CaptureKind) async throws -> Data
    func delete(id: String) async throws
}
// -Nimah: Mock lama tetap menolak operasi yang belum didukung; tidak ada sukses palsu.
extension SavedLooksStoring {
    func save(referenceID: String, before: Data, after: Data) async throws -> SavedLookMetadata { throw SavedLooksError.notImplemented }
    func imageData(for lookID: String, kind: CaptureKind) async throws -> Data { throw SavedLooksError.notImplemented }
    func delete(id: String) async throws { throw SavedLooksError.notImplemented }
}
