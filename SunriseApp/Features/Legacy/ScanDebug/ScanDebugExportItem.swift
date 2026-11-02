import CoreGraphics
import CoreTransferable

/// What the share sheet sends. The picture is encoded only when the person picks a destination, and the system writes it to its
/// own temporary file; nothing is written by the app before that.
struct ScanDebugExportItem: Transferable, Sendable {
    let name: String
    let raw: ScanDebugPointSet
    let corrected: ScanDebugPointSet
    let picture: CGImage

    var fileName: String { "\(raw.kind.rawValue)-\(name)" }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .sunriseScan) { item in
            try ScanDebugExportFile(name: item.name, raw: item.raw, corrected: item.corrected, picture: item.picture).encoded()
        }
        .suggestedFileName { $0.fileName }
    }
}
