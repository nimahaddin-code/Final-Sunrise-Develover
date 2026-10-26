import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var library: ScanLibrary
    @State private var isImporting = false
    @State private var isChoosingOutput = false

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let item = library.selectedItem {
                EditorView(item: item, model: item.model, library: library).id(item.id)
            } else {
                ContentUnavailableView {
                    Label("No scan open", systemImage: "face.dashed")
                } description: {
                    Text("AirDrop a scan from the iPhone app's Scan Debug tab (Export for Mac), then open it here or drop it on this window.")
                } actions: {
                    Button("Open…") { isImporting = true }
                }
            }
        }
        .toolbar {
            ToolbarItem { Button { isImporting = true } label: { Label("Open", systemImage: "folder") }.keyboardShortcut("o") }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.sunriseScan, .json, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.open(urls) }
        }
        .fileImporter(isPresented: $isChoosingOutput, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.setOutputDirectory(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in library.open(urls); return true }
        .navigationTitle("Sunrise Scan Editor")
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $library.selection) {
                ForEach(library.items) { item in
                    HStack {
                        Image(systemName: item.file.kind == .face ? "face.smiling" : "eye")
                        VStack(alignment: .leading) {
                            Text(item.title).lineLimit(1)
                            Text(item.file.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !item.model.savedFiles.isEmpty { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .tag(item.id)
                    .contextMenu { Button("Close") { library.close(item) } }
                }
            }
            if !library.problems.isEmpty {
                Text(library.problems.joined(separator: "\n")).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Corrections are saved in").font(.caption).foregroundStyle(.secondary)
                Text(library.outputDirectory.path).font(.caption2.monospaced()).lineLimit(2).truncationMode(.middle)
                HStack {
                    Button("Change…") { isChoosingOutput = true }
                    Button("Show") { NSWorkspace.shared.open(library.outputDirectory) }
                }
                .controlSize(.small)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
