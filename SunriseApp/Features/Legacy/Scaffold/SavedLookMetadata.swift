// -Nimah: SavedLookMetadata.swift — implementasi MVP SunriseApp.
import Foundation

struct SavedLookMetadata: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let referenceID: String
    let createdAt: Date
}
enum CaptureKind: String, Sendable { case before, after }
