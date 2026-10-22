// -Nimah: Local palette photo sampling; images stay in memory and are never uploaded or saved.
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

struct PaletteColorPicker: View {
    let initial: MakeupShade
    let onApply: (MakeupShade)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var color: Color
    @State private var photo: PalettePhoto?
    @State private var selection: PhotosPickerItem?
    @State private var showCamera=false
    @State private var loading=false
    @State private var error: String?
    @State private var marker: CGPoint?
    @State private var loadTask: Task<Void,Never>?
    @State private var requestID=UUID()

    init(initial:MakeupShade,onApply:@escaping (MakeupShade)->Void) {
        self.initial=initial;self.onApply=onApply;_color=State(initialValue:initial.color)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:AppSpacing.medium) {
                    ColorPicker("Choose makeup colour",selection:$color,supportsOpacity:false)
                    HStack {
                        PhotosPicker(selection:$selection,matching:.images) { Label("Palette from Photos",systemImage:"photo") }
                        Spacer()
                        Button { Task { await takePhoto() } } label: { Label("Photograph palette",systemImage:"camera") }
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    }.font(AppTypography.caption)
                    if loading { ProgressView("Loading palette") }
                    if let photo {
                        Text("Tap a colour on your palette photo").font(AppTypography.body)
                        GeometryReader { proxy in
                            ZStack {
                                Color.gray.opacity(0.12)
                                Image(decorative:photo.image,scale:1).resizable().scaledToFit()
                                if let marker {
                                    Circle().strokeBorder(.white,lineWidth:3).background(Circle().fill(color))
                                        .frame(width:24,height:24).shadow(radius:2).position(marker)
                                }
                            }.contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { tap in
                                    if let picked=photo.sample(at:tap.location,in:proxy.size) { color=Color(uiColor:picked);marker=tap.location }
                                })
                                .accessibilityLabel("Palette photo. Tap a colour, or use the colour picker above.")
                        }.frame(height:300)
                    }
                    if let error { Text(error).font(AppTypography.caption).foregroundStyle(.red) }
                    HStack { Circle().fill(color).frame(width:40,height:40);Text("Selected colour") }
                    Text("Photo colours are approximate: lighting and the camera affect the result. Photos stay on this device and are not saved by the app.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                    Button("Use this colour") {
                        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
                        guard UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a) else { return }
                        onApply(MakeupShade(id:"custom."+UUID().uuidString,name:"Custom colour",red:r,green:g,blue:b,opacity:initial.opacity))
                        dismiss()
                    }.buttonStyle(.borderedProminent).tint(AppColors.rose).disabled(loading)
                }.padding(AppSpacing.medium)
            }.navigationTitle("Makeup colour").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .sheet(isPresented:$showCamera) {
            PaletteCamera { image in
                showCamera=false
                if let image { load(image) }
            }.ignoresSafeArea()
        }
        .task(id:selection) {
            guard let selection else { return }
            requestID=UUID();let request=requestID
            loading=true;error=nil
            do {
                guard let data=try await selection.loadTransferable(type:Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let decoded=await Task.detached(priority:.userInitiated) { PalettePhoto.decode(data) }.value
                guard !Task.isCancelled,request==requestID else { return }
                photo=decoded;marker=nil;loading=false
                if decoded == nil { error=String(localized:"Could not open this photo. Try another image.") }
            } catch { if !Task.isCancelled,request==requestID { loading=false;self.error=String(localized:"Could not open this photo. Try another image.") } }
        }
        .onDisappear { loadTask?.cancel() }
    }
    private func takePhoto() async {
        requestID=UUID();loading=false
        let allowed:Bool
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:allowed=true
        case .notDetermined:allowed=await AVCaptureDevice.requestAccess(for:.video)
        default:allowed=false
        }
        if allowed { showCamera=true } else { error=String(localized:"Allow camera access in Settings to photograph your palette.") }
    }
    private func load(_ image:UIImage) {
        struct ImmutablePhoto: @unchecked Sendable { let image:UIImage }
        let box=ImmutablePhoto(image:image)
        requestID=UUID();let request=requestID
        loading=true;error=nil;loadTask?.cancel()
        loadTask=Task {
            let decoded=await Task.detached(priority:.userInitiated) { box.image.jpegData(compressionQuality:0.9).flatMap(PalettePhoto.decode) }.value
            guard !Task.isCancelled,request==requestID else { return }
            photo=decoded;marker=nil;loading=false
            if decoded == nil { error=String(localized:"Could not open this photo. Try another image.") }
        }
    }
}

// -Nimah: Rear-camera capture reuses the existing camera permission; no photo-library write occurs.
private struct PaletteCamera:UIViewControllerRepresentable {
    let completion:(UIImage?)->Void
    func makeCoordinator()->Coordinator { Coordinator(completion:completion) }
    func makeUIViewController(context:Context)->UIImagePickerController {
        let picker=UIImagePickerController();picker.sourceType = .camera;picker.cameraDevice = .rear;picker.delegate=context.coordinator
        return picker
    }
    func updateUIViewController(_ controller:UIImagePickerController,context:Context) {}
    final class Coordinator:NSObject,UIImagePickerControllerDelegate,UINavigationControllerDelegate {
        let completion:(UIImage?)->Void
        init(completion:@escaping (UIImage?)->Void) { self.completion=completion }
        func imagePickerControllerDidCancel(_ picker:UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker:UIImagePickerController,didFinishPickingMediaWithInfo info:[UIImagePickerController.InfoKey:Any]) { completion(info[.originalImage] as? UIImage) }
    }
}
