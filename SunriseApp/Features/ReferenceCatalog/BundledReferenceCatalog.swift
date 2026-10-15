// -Nimah: BundledReferenceCatalog.swift — implementasi MVP SunriseApp.
struct BundledReferenceCatalog: ReferenceCatalogProviding {
    static let looks: [MakeupReference] = [
        .init(id: "douyin", name: "Douyin", summary: "Rosy cheeks · dreamy eyes"),
        .init(id: "clean-girl", name: "Clean Girl", summary: "Fresh skin · soft definition"),
        .init(id: "soft-glam", name: "Soft Glam", summary: "Velvet rose · subtle shimmer"),
        .init(id: "latte", name: "Latte", summary: "Warm bronze · caramel tones")
    ]
    func references() async throws -> [MakeupReference] { Self.looks }
    static func look(id: String) -> MakeupReference? { looks.first { $0.id == id } }
}
