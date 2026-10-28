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

/// The sheet behind the "+" button: photograph a makeup product, then drag the pin to the colour to use.
/// Photos stay in memory and are never saved or uploaded.
struct PaletteColorPicker: View {
    let initial: MakeupShade
    let onApply: (MakeupShade) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ProductCamera()
    @State private var photo: PalettePhoto?
    @State private var marker: CGPoint?
    @State private var color: Color
    @State private var selection: PhotosPickerItem?
    @State private var error: String?

    private static let frameSize = CGSize(width: 280, height: 294)
    private static let pinSize: CGFloat = 40

    init(initial: MakeupShade, onApply: @escaping (MakeupShade) -> Void) {
        self.initial = initial
        self.onApply = onApply
        _color = State(initialValue: initial.color)
    }

    var body: some View {
        VStack(spacing: AppSpacing.large) {
            Text(photo == nil ? "Snap Your Product" : "Pick Your Colour")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            viewfinder
            if let error {
                Text(error).font(AppTypography.caption).multilineTextAlignment(.center)
            }
            controls
        }
        .padding(.top, AppSpacing.extraLarge)
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(AppColors.snow)
        .presentationBackground(AppColors.screen)
        .presentationDetents([.height(600), .large])
        .presentationCornerRadius(32)
        .presentationDragIndicator(.visible)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .task(id: selection) { await loadSelection() }
    }

    // MARK: Viewfinder and photo

    private var viewfinder: some View {
        ZStack {
            if let photo {
                pickSurface(photo)
            } else {
                switch camera.state {
                case .running: ProductCameraPreview(session: camera.session)
                case .idle: ProgressView().tint(AppColors.snow)
                case .denied: unavailable("Allow camera access in Settings to photograph your product.")
                case .unavailable: unavailable("The camera is not available. You can choose a photo instead.")
                }
            }
        }
        .frame(width: Self.frameSize.width, height: Self.frameSize.height)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
    }

    private func pickSurface(_ photo: PalettePhoto) -> some View {
        ZStack {
            Image(decorative: photo.image, scale: 1).resizable().scaledToFit()
            if let marker {
                pin.position(x: marker.x, y: marker.y - (Self.pinSize + 18) / 2)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            if let picked = photo.sample(at: drag.location, in: Self.frameSize) {
                color = Color(uiColor: picked)
                marker = drag.location
            }
        })
        .accessibilityLabel("Product photo. Drag the pin to a colour.")
    }

    /// A teardrop pin whose tip sits on the sampled point and whose head shows the colour under it.
    private var pin: some View {
        ZStack(alignment: .top) {
            PinTip().fill(AppColors.snow).frame(width: 22, height: 26).offset(y: Self.pinSize - 10)
            Circle().fill(AppColors.snow).frame(width: Self.pinSize, height: Self.pinSize)
                .overlay(Circle().fill(color).padding(4))
        }
        .frame(width: Self.pinSize, height: Self.pinSize + 18, alignment: .top)
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .allowsHitTesting(false)
    }

    private func unavailable(_ message: LocalizedStringKey) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "camera").font(.largeTitle).accessibilityHidden(true)
            Text(message).font(AppTypography.caption).multilineTextAlignment(.center)
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Choose from Photos", systemImage: "photo")
            }
            .buttonStyle(.borderedProminent).tint(AppColors.flamingo)
        }
        .padding(AppSpacing.medium)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if photo == nil {
            Button(action: snap) {
                ZStack {
                    Circle().strokeBorder(AppColors.snow, lineWidth: 3).frame(width: 76, height: 76)
                    Circle().fill(AppColors.flamingo.opacity(0.6)).frame(width: 60, height: 60)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running)
            .opacity(camera.state == .running ? 1 : 0.4)
            .accessibilityLabel("Take photo of product")
        } else {
            HStack(spacing: AppSpacing.large) {
                roundButton("arrow.counterclockwise", label: "Retake", action: retake)
                Circle().fill(color).frame(width: 60, height: 60)
                    .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: 2))
                    .accessibilityLabel("Selected colour")
                roundButton("checkmark", label: "Use this colour", action: apply)
            }
        }
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
                .background(AppColors.flamingo, in: Circle())
                .foregroundStyle(AppColors.snow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Actions

    private func snap() {
        guard let data = camera.snapshot(aspect: Self.frameSize.width / Self.frameSize.height) else {
            error = String(localized: "Could not take the photo. Try again.")
            return
        }
        camera.stop()
        Task { await show(data) }
    }

    private func retake() {
        photo = nil; marker = nil; error = nil; selection = nil
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
        let centre = CGPoint(x: Self.frameSize.width / 2, y: Self.frameSize.height / 2)
        if let picked = decoded.sample(at: centre, in: Self.frameSize) {
            color = Color(uiColor: picked)
            marker = centre
        }
    }
}

private struct PinTip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
