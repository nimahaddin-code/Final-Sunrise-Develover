import AppKit
import Combine
import SwiftUI

/// The scans opened in the editor and the folder the corrections are written to.
@MainActor final class ScanLibrary: ObservableObject {
    struct Item: Identifiable {
        let id: URL
        let file: ScanDebugExportFile
        let model: ScanDebugViewModel
        var title: String { file.name }
    }

    private static let outputKey = "outputDirectory"

    @Published private(set) var items: [Item] = []
    @Published var selection: URL?
    @Published private(set) var problems: [String] = []
    @Published private(set) var outputDirectory: URL
    let store: ScanDebugStore

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.outputKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sunrise Scan Corrections", isDirectory: true)
        let directory = saved ?? fallback
        outputDirectory = directory
        store = ScanDebugStore(directory: directory)
    }

    var selectedItem: Item? { items.first { $0.id == selection } }

    func setOutputDirectory(_ url: URL) {
        outputDirectory = url
        UserDefaults.standard.set(url.path, forKey: Self.outputKey)
        store.use(directory: url)
    }

    /// Opens scan files, or every scan file inside the folders given.
    func open(_ urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let found = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
                    .compactMap { $0 as? URL }.filter { $0.pathExtension == ScanDebugExportFile.fileExtension } ?? []
                files += found.sorted { $0.path < $1.path }
            } else {
                files.append(url)
            }
        }
        var newProblems: [String] = []
        for url in files where !items.contains(where: { $0.id == url }) {
            do {
                items.append(try Self.load(url, store: store))
                selection = url
            } catch {
                newProblems.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }
        problems = newProblems
    }

    func close(_ item: Item) {
        items.removeAll { $0.id == item.id }
        if selection == item.id { selection = items.first?.id }
    }

    static func load(_ url: URL, store: ScanDebugStore) throws -> Item {
        let file = try ScanDebugExportFile.decode(Data(contentsOf: url))
        guard let picture = file.picture() else { throw ScanDebugExportFile.Failure.unreadablePicture }
        let model = ScanDebugViewModel(store: store)
        model.load(raw: file.rawSet, corrected: file.correctedSet, picture: picture)
        model.saveName = file.name
        model.stage = .corrected
        model.beginEditing()
        return Item(id: url, file: file, model: model)
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case ScanDebugExportFile.Failure.notAScanFile: "not a Sunrise scan file"
        case ScanDebugExportFile.Failure.pointsOnly:
            "this is a saved points file with no picture, so it can't be edited. On the iPhone, use Export for Mac (or Export all) and open the .sunrisescan file"
        case ScanDebugExportFile.Failure.newerVersion(let version): "made by a newer app (format \(version)); update this editor"
        case ScanDebugExportFile.Failure.unreadablePicture: "the picture inside could not be read"
        default: error.localizedDescription
        }
    }
}
