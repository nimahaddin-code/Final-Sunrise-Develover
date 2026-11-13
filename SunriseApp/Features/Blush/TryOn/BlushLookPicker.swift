import SwiftUI

// -Nimah: Placement and shade are independent. The looks are `BlushPlacementStyle.referenceLooks`, in the design order.
/// The blush looks as glass circles over the bottom of the camera card; the first circle is no blush (`nil`).
/// Moved from TryOnHomeView unchanged, so the blush owner edits blush choices without touching the Try On screen.
struct BlushLookPicker: View {
    /// The look on the face, nil when blush is off.
    let selected: BlushPlacementStyle?
    let onSelect: (BlushPlacementStyle?) -> Void

    var body: some View {
        GlassPickerRow(selectedID: selected.map { "\($0.id)" } ?? "none", onCenter: { id in
            onSelect(BlushPlacementStyle.referenceLooks.first(where: { $0.id == id }))
        }) {
            Button { onSelect(nil) } label: {
                StyleCircle(selected: selected == nil, isNone: true) { EmptyView() }
            }
            .buttonStyle(.plain).id("none").accessibilityLabel("No makeup")
            ForEach(BlushPlacementStyle.referenceLooks) { look in
                let isSelected = selected == look
                Button { onSelect(look) } label: {
                    StyleCircle(selected: isSelected) { BlushStyleIcon(look: look) }
                }
                .buttonStyle(.plain)
                .id("\(look.id)")
                .accessibilityLabel(look.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
