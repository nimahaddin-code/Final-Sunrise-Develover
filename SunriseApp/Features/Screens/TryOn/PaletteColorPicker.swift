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
/// button at the left), then drag the pin to the colour to use. Photos stay in memory and are never saved or uploaded.

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

    private static let frameSize = CGSize(width: 340, height: 460)
    private static let pinSize: CGFloat = 40
    /// The pin's tip sits this far above the finger, so the tip and the colour under it stay in view while dragging.
    private static let fingerGap: CGFloat = 56

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
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text(photo == nil ? "Add your \(featureName) colour" : "Select Your Shade")
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
            if photo == nil && camera.state == .running {
                Text("Point your camera at a product or a swatch on skin.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.snow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.medium).padding(.vertical, 12)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(AppSpacing.medium)
            }
        }
        .frame(width: Self.frameSize.width, height: Self.frameSize.height)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            let tip = CGPoint(x: drag.location.x, y: drag.location.y - Self.fingerGap)
            if let picked = photo.sample(at: tip, in: Self.frameSize) {
                color = Color(uiColor: picked)
                marker = tip
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
            .buttonStyle(.borderedProminent).tint(AppColors.buttonInk)
        }
        .padding(AppSpacing.medium)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if photo == nil {
            HStack {
                Button { showsLibrary = true } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .regular))
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose from Photos")
                Spacer()
                Button(action: snap) {
                    ZStack {
                        Circle().strokeBorder(AppColors.buttonInk, lineWidth: 5).frame(width: 84, height: 84)
                        Circle().fill(AppColors.buttonInk).frame(width: 66, height: 66)
                    }
                }
                .buttonStyle(.plain)
                .disabled(camera.state != .running)
                .opacity(camera.state == .running ? 1 : 0.4)
                .accessibilityLabel("Take photo of product")
                Spacer()
                // Keeps the shutter in the middle.
                Color.clear.frame(width: 56, height: 56)
            }
            .padding(.horizontal, AppSpacing.small)
        } else {
            HStack {
                roundButton("arrow.counterclockwise", label: "Retake", action: retake)
                Spacer()
                Button(action: apply) {
                    Text("Done").font(.headline).foregroundStyle(AppColors.snow)
                        .padding(.horizontal, 28).frame(height: 48)
                        .glassEffect(.regular.tint(AppColors.buttonInk).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use this colour")
            }
            .padding(.horizontal, AppSpacing.small)
        }
    }

    private func roundButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        GlassCircleButton(symbol: symbol, size: 48, tint: Color.black.opacity(0.12), label: label, action: action)
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
