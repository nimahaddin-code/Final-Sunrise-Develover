import Foundation

enum SampleData {
    static let references: [MakeupReference] = [
        .init(id: "douyin", name: "Douyin", summary: "Rosy cheeks and soft shimmer"),
        .init(id: "clean-girl", name: "Clean Girl", summary: "Fresh skin and subtle definition"),
        .init(id: "soft-glam", name: "Soft Glam", summary: "Velvet rose and blended eyes"),
        .init(id: "latte", name: "Latte", summary: "Warm bronze and caramel tones")
    ]
    static let savedLook = SavedLookMetadata(
        id: "sample-look-douyin", referenceID: "douyin",
        createdAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}
