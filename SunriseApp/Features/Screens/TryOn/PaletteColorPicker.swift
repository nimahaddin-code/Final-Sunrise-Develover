// -Nimah: Local palette photo sampling (sampler); the sheet below follows the design's snap-then-pick flow. images stay in memory and are never uploaded or saved.
import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import ImageIO

/// Upright, bounded sRGB pixels shared by the display and sampler, so EXIF rotation cannot shift the picked colour.
struct PalettePhoto: @unchecked Sendable {
    let image: CGImage
    let rgba: [UInt8]
    var width: Int { image.width }
    var height: Int { image.height }

    static func decode(_ data: Data) -> PalettePhoto? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:1024
              ] as CFDictionary),let space=CGColorSpace(name:CGColorSpace.sRGB) else { return nil }
        let w=thumbnail.width,h=thumbnail.height
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let rendered:CGImage?=bytes.withUnsafeMutableBytes { memory in
            guard let context=CGContext(data:memory.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(thumbnail,in:CGRect(x:0,y:0,width:w,height:h))
            return context.makeImage()
        }
        guard let rendered else { return nil }
        return PalettePhoto(image:rendered,rgba:bytes)
    }

    static func imageRect(image:CGSize,in bounds:CGSize)->CGRect {
        guard image.width>0,image.height>0,bounds.width>0,bounds.height>0 else { return .zero }
        let scale=min(bounds.width/image.width,bounds.height/image.height)
        let size=CGSize(width:image.width*scale,height:image.height*scale)
        return CGRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height)
    }

    func sample(at point:CGPoint,in bounds:CGSize)->UIColor? {
        let rect=Self.imageRect(image:CGSize(width:width,height:height),in:bounds)
        guard rect.width>0,rect.contains(point) else { return nil }
        let x=min(width-1,Int((point.x-rect.minX)/rect.width*Double(width)))
        let y=min(height-1,Int((point.y-rect.minY)/rect.height*Double(height)))
        // A small patch reduces sensor noise without averaging an entire makeup pan into its packaging.
        var r=0.0,g=0.0,b=0.0,n=0.0
        for row in max(0,y-1)...min(height-1,y+1) {
            for col in max(0,x-1)...min(width-1,x+1) {
                let i=(row*width+col)*4,alpha=Double(rgba[i+3])/255
                guard alpha>0.1 else { continue }
                r+=Double(rgba[i])/alpha;g+=Double(rgba[i+1])/alpha;b+=Double(rgba[i+2])/alpha;n+=1
            }
        }
        guard n>0 else { return nil }
        return UIColor(red:min(r/n/255,1),green:min(g/n/255,1),blue:min(b/n/255,1),alpha:1)
    }
}

/// The sheet behind the "+" button, opened on the back camera: photograph a makeup product (or pick a photo with the
/// button at the left), then drag the loupe to the colour to use. Photos stay in memory and are never saved or uploaded.

struct PaletteColorPicker: View {
    let initial: MakeupShade
    /// "blush", "brow" or "eyeliner", for the title.
    let featureName: String
    let onApply: (MakeupShade) -> Void
    @State private var showsLibrary = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ProductCamera()
    @State private var photo: PalettePhoto?
    @State private var marker: CGPoint?
    @State private var color: Color
    @State private var selection: PhotosPickerItem?
    @State private var error: String?

    /// Measured from the available width (aspect 0.8); the default is used until the first layout.
    @State private var frameSize = CGSize(width: 340, height: 425)
    /// Where the loupe was when the current drag began.
    @State private var dragAnchor: CGPoint?
    private static let loupeSize: CGFloat = 96

    init(initial: MakeupShade, featureName: String, onApply: @escaping (MakeupShade) -> Void) {
        self.initial = initial
        self.featureName = featureName
        self.onApply = onApply
        _color = State(initialValue: initial.color)
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            header
            viewfinder
            if let error {
                Text(error).font(AppTypography.caption).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(.top, AppSpacing.medium)
        .padding(.bottom, AppSpacing.large)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The viewfinder takes the sheet's width (12 pt each side) at 4:5, shorter on small screens so the buttons fit.
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { sheet in
            let width = max(sheet.width - 24, 1)
            frameSize = CGSize(width: width, height: max(min(width / 0.8, sheet.height - 300), 200).rounded())
        }
        .foregroundStyle(AppColors.onboardingInk)
        .environment(\.colorScheme, .light)
        .presentationBackground(Color.white)
        .presentationDetents([.large])
        .presentationCornerRadius(40)
        .presentationDragIndicator(.visible)
        .task { await camera.start() }
        .photosPicker(isPresented: $showsLibrary, selection: $selection, matching: .images)
        .onDisappear { camera.stop() }
        .task(id: selection) { await loadSelection() }
    }

    /// Close at the left, the title in the middle.
    private var header: some View {
        ZStack {
            Text("Pick your \(featureName) colour")
                .font(.system(size: 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.top, AppSpacing.small)
    }

    // MARK: Viewfinder and photo

    private var viewfinder: some View {
        ZStack {
            if let photo {
                pickSurface(photo)
            } else {
                switch camera.state {
                case .running: ProductCameraPreview(session: camera.session)
                case .idle: ProgressView()
                case .denied: unavailable("Allow camera access in Settings to photograph your product.")
                case .unavailable: unavailable("The camera is not available. You can choose a photo instead.")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if photo != nil || camera.state == .running {
                Text(photo == nil ? "Point your camera at a product or a swatch on skin." : "Tap and drag the circle to pick the color.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.snow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(AppSpacing.medium)
            }
        }
        .overlay(alignment: .topLeading) {
            if photo == nil && camera.state == .running && camera.hasTorch {
                overlayCircle(systemImage: camera.torchOn ? "bolt.fill" : "bolt.slash.fill", label: "Torch", action: camera.toggleTorch)
                    .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if photo == nil && camera.state == .running {
                overlayCircle(text: camera.zoomed ? "2x" : "1x", label: "Zoom", action: camera.toggleZoom).padding(12)
            }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .background(Color(white: 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func overlayCircle(systemImage: String? = nil, text: String? = nil, label: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)) }
                else if let text { Text(text).font(.system(size: 13, weight: .semibold)) }
            }
            .foregroundStyle(AppColors.snow)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pickSurface(_ photo: PalettePhoto) -> some View {
        ZStack {
            Image(decorative: photo.image, scale: 1).resizable().scaledToFit()
            if let marker { loupe.position(marker) }
        }
        .frame(width: frameSize.width, height: frameSize.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            if dragAnchor == nil {
                // Grabbing the loupe moves it from where it is; elsewhere it jumps to the touch, then follows.
                if let marker, hypot(drag.startLocation.x - marker.x, drag.startLocation.y - marker.y) <= Self.loupeSize / 2 {
                    dragAnchor = marker
                } else {
                    dragAnchor = drag.startLocation
                }
            }
            guard let anchor = dragAnchor else { return }
            let rect = PalettePhoto.imageRect(image: CGSize(width: photo.width, height: photo.height), in: frameSize)
            let point = CGPoint(x: min(max(anchor.x + drag.translation.width, rect.minX), rect.maxX - 0.5),
                                y: min(max(anchor.y + drag.translation.height, rect.minY), rect.maxY - 0.5))
            if let picked = photo.sample(at: point, in: frameSize) {
                color = Color(uiColor: picked)
                marker = point
            }
        }.onEnded { _ in dragAnchor = nil })
        .accessibilityLabel("Product photo. Drag the circle to a colour.")
    }

    /// A see-through loupe centred on the sampled point: only its rings and cross are drawn.
    private var loupe: some View {
        ZStack {
            Circle().strokeBorder(AppColors.snow, lineWidth: 4)
            Circle().strokeBorder(AppColors.snow, lineWidth: 1.5).frame(width: 60, height: 60)
            Rectangle().fill(AppColors.snow).frame(width: 18, height: 2)
            Rectangle().fill(AppColors.snow).frame(width: 2, height: 18)
        }
        .frame(width: Self.loupeSize, height: Self.loupeSize)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        .allowsHitTesting(false)
    }

    private func unavailable(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "camera").font(.largeTitle).accessibilityHidden(true)
            Text(message).font(AppTypography.caption).multilineTextAlignment(.center)
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Choose from Photos", systemImage: "photo")
            }
            .buttonStyle(.borderedProminent).tint(AppColors.buttonInk)
        }
        .padding(AppSpacing.medium)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if photo == nil {
            HStack {
                greyCircle("photo.badge.plus", label: "Choose from Photos") { showsLibrary = true }
                Spacer()
                Button(action: snap) {
                    ZStack {
                        Circle().strokeBorder(Color.black, lineWidth: 5).frame(width: 84, height: 84)
                        Circle().fill(Color.black).frame(width: 66, height: 66)
                    }
                }
                .buttonStyle(.plain)
                .disabled(camera.state != .running)
                .opacity(camera.state == .running ? 1 : 0.4)
                .accessibilityLabel("Take photo of product")
                Spacer()
                greyCircle("arrow.triangle.2.circlepath", label: "Switch camera", action: camera.flip)
                    .disabled(camera.state != .running)
                    .opacity(camera.state == .running ? 1 : 0.4)
            }
            .padding(.horizontal, AppSpacing.small)
        } else {
            VStack(spacing: AppSpacing.medium) {
                Button(action: retake) {
                    Label("Retake", systemImage: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(AppColors.dandanPink)
                }
                .buttonStyle(.plain)
                Button(action: apply) {
                    Text("Add this colour").font(.system(size: 17, weight: .semibold)).foregroundStyle(AppColors.snow)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(AppColors.buttonInk, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add this colour")
            }
        }
    }

    private func greyCircle(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(AppColors.buttonInk)
                .frame(width: 84, height: 84)
                .background(Color(white: 0.96), in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func snap() {
        guard let data = camera.snapshot(aspect: frameSize.width / frameSize.height) else {
            error = String(localized: "Could not take the photo. Try again.")
            return
        }
        camera.stop()
        Task { await show(data) }
    }

    private func retake() {
        photo = nil; marker = nil; dragAnchor = nil; error = nil; selection = nil
        Task { await camera.start() }
    }

    private func apply() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        onApply(MakeupShade(id: "custom." + UUID().uuidString, name: "Custom colour", red: r, green: g, blue: b,
                            opacity: initial.opacity))
        dismiss()
    }

    private func loadSelection() async {
        guard let selection else { return }
        error = nil
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
            camera.stop()
            await show(data)
        } catch {
            if !Task.isCancelled { self.error = String(localized: "Could not open this photo. Try another image.") }
        }
    }

    /// Decodes the photo off the main thread and puts the pin in its middle.
    private func show(_ data: Data) async {
        let decoded = await Task.detached(priority: .userInitiated) { PalettePhoto.decode(data) }.value
        guard let decoded else {
            error = String(localized: "Could not open this photo. Try another image.")
            return
        }
        photo = decoded
        error = nil
        let centre = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)
        if let picked = decoded.sample(at: centre, in: frameSize) {
            color = Color(uiColor: picked)
            marker = centre
        }
    }
}
