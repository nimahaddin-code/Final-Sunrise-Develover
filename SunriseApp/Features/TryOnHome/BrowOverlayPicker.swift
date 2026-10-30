import SwiftUI

/// Horizontal list of the brow pictures, shown under the tool strip while the eyebrow tool is selected. The chosen
/// picture is drawn over the user's (hidden) natural brow.
struct BrowOverlayPicker: View {
    let overlays: [BrowOverlay]
    let selected: BrowOverlay?
    let onSelect: (BrowOverlay?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                // First: no overlay picture. The natural brow stays as the "Natural brow" toggle has it.
                let noneSelected = selected == nil
                Button { onSelect(nil) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "nosign").font(.title2).frame(width: 96, height: 34)
                        Text("None").font(AppTypography.caption.weight(.semibold))
                    }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(AppColors.flamingo.opacity(noneSelected ? 0.32 : 0.16),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppColors.snow, lineWidth: noneSelected ? 2 : 0)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("No brow overlay"))
                .accessibilityAddTraits(noneSelected ? .isSelected : [])
                ForEach(overlays) { overlay in
                    let isSelected = overlay == selected
                    Button { onSelect(overlay) } label: {
                        VStack(spacing: 4) {
                            Image(overlay.assetName)
                                .resizable().scaledToFit()
                                .frame(width: 96, height: 34)
                                .overlay(alignment: .topTrailing) {
                                    if overlay.is3D {
                                        Text("3D").font(AppTypography.caption.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(AppColors.snow.opacity(0.9), in: Capsule()).foregroundStyle(AppColors.screen)
                                            .offset(x: 10, y: -8)
                                    }
                                }
                            Text(overlay.title).font(AppTypography.caption.weight(.semibold))
                        }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(AppColors.flamingo.opacity(isSelected ? 0.32 : 0.16),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AppColors.snow, lineWidth: isSelected ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(overlay.title))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
