import Combine

@MainActor final class ReferenceCatalogViewModel: ObservableObject {
    enum State: Equatable { case idle, loading, loaded([MakeupReference]), failed }
    @Published private(set) var state: State = .idle
    private let service: any ReferenceCatalogProviding
    init(service: any ReferenceCatalogProviding) { self.service = service }
    func load() async {
        guard state != .loading else { return }
        state = .loading
        do { state = .loaded(try await service.references()) }
        catch is CancellationError { state = .idle }
        catch { state = .failed }
    }
}
