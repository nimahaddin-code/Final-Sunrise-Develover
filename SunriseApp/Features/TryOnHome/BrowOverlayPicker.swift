import SwiftUI

/// The brow pictures as glass circles over the bottom of the camera card while the eyebrow tool is selected, the chosen
/// one in the middle. The chosen picture is drawn over the user's (hidden) natural brow; its name shows above the row.
struct BrowOverlayPicker: View {
    let overlays: [BrowOverlay]
    let selected: BrowOverlay?
    let onSelect: (BrowOverlay?) -> Void

    var body: some View {
        GlassPickerRow(title: selected.map { Text($0.title) } ?? Text("None"), selectedID: selected?.assetName ?? "none", onCenter: { id in
            onSelect(overlays.first { $0.assetName == id })
        }) {
            // First: no overlay picture. The natural brow stays as the "Natural brow" toggle has it.
            Button { onSelect(nil) } label: {
                StyleCircle(selected: selected == nil, isNone: true) { EmptyView() }
            }
            .buttonStyle(.plain)
            .id("none")
            .accessibilityLabel(Text("No brow overlay"))
            .accessibilityAddTraits(selected == nil ? .isSelected : [])
            ForEach(overlays) { overlay in
                let isSelected = overlay == selected
                Button { onSelect(overlay) } label: {
                    StyleCircle(selected: isSelected) { BrowStyleIcon(assetName: overlay.assetName) }
                }
                .buttonStyle(.plain)
                .id(overlay.assetName)
                .accessibilityLabel(Text(overlay.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
