import Foundation

/// Metadata only. Capture files and persistence belong to a future milestone.
struct SavedLookMetadata: Identifiable, Hashable, Sendable {
    let id: String
    let referenceID: String
    let createdAt: Date
}
