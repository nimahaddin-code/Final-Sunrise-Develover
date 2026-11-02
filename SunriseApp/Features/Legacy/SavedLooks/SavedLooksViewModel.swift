import Combine

@MainActor final class SavedLooksViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded([SavedLookMetadata]), failed }
    @Published private(set) var state: State = .idle
    private let store: any SavedLooksStoring
    init(store: any SavedLooksStoring) { self.store = store }
    func load() async {
        guard state != .loading else { return }
        state = .loading
        do { state = .loaded(try await store.list()) }
        catch is CancellationError { state = .idle }
        catch { state = .failed }
    }
}
