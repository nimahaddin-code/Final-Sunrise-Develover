// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): test fixtures for the brow pipelines.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

#if DEBUG
extension BeautyBlushEngine {
    /// The production brow texture bake for `style`, read back as RGBA floats (`width` x `height`).
    static func renderBrowTextureFixture(style:EyebrowStyle,width:Int=256,height:Int=128)throws->[Float] {
        let engine=try BeautyBlushEngine(),d=engine.device
        guard let design=BrowDesign.make(style:style) else {throw CocoaError(.coderInvalidValue)}
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:width,height:height,mipmapped:false);desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
        guard let target=d.makeTexture(descriptor:desc),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        try engine.encodeBrowTexture(design,into:target,command:command)
        command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var raw=Array(repeating:UInt16(0),count:width*height*4)
        raw.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:width*8,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)}
        return raw.map {Float(Float16(bitPattern:$0))}
    }
    /// The production brow strip pipeline over a synthetic camera: a strip quad at the brow centre fills most of
    /// the target, and the brow texture holds `textureValue` in every channel. `darkBrow` puts a dark band (the natural
    /// brow) across the middle rows of the camera; `hideNatural` turns on hiding it, with the brow shape off.
    static func renderBrowStripFixture(obstructed:Bool,intensity:Float,textureValue:UInt8=255,darkBrow:Bool=false,hideNatural:Bool=false)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=32
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,(0..<n*n).map {darkBrow && (12..<20).contains($0/n) ? 40:180},n)
        let cb=try texture(.rg8Unorm,Array(repeating:128,count:n*n*2),n*2)
        let mask=try texture(.r8Unorm,Array(repeating:obstructed ? 255:0,count:n*n),n)
        let brow=try texture(.rgba8Unorm,Array(repeating:textureValue,count:n*n*4),n*4)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let corners:[SIMD2<Float>]=[.init(-0.8,-0.8),.init(0.8,-0.8),.init(0.8,0.8),.init(-0.8,0.8)]
        let points=corners.map {BrowVertex(position:SIMD4($0.x,$0.y,0,1),brow:SIMD4(0.5,0,0.1,1),probes:SIMD4(0.5,0.4,0.5,0.6),
                                           skin:SIMD4(0.05,0.05,0,0),conceal:SIMD4(0.16,0.3,0,0.17))}
        let tris:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=tris.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.05,0.03,0.02,intensity),controls:SIMD4(0.9,0.65,0.85,0.68),tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,1),stretch:SIMD4(0.45,0.7,1.45,1.85),
                       debug:SIMD4(0,hideNatural ? 1:0,hideNatural ? 0:1,0))
        var extent=browExtent
        // The eraser's fill, here the camera's bright skin colour (linear) in both brow slices.
        let fillDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:4,height:4,mipmapped:false)
        fillDescriptor.textureType = .type2DArray;fillDescriptor.arrayLength=2;fillDescriptor.usage = .shaderRead;fillDescriptor.storageMode = .shared
        guard let fill=d.makeTexture(descriptor:fillDescriptor) else {throw CocoaError(.featureUnsupported)}
        let skinValue=Float16(BeautyBlushConfiguration.linear(180/255)).bitPattern,one=Float16(1).bitPattern
        let fillTexels=(0..<16).flatMap {_ in [skinValue,skinValue,skinValue,one]}
        for slice in 0..<2 {fillTexels.withUnsafeBytes {fill.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,slice:slice,withBytes:$0.baseAddress!,bytesPerRow:32,bytesPerImage:128)}}
        var space=BrowEraser.space
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        e.setRenderPipelineState(engine.background);e.setDepthStencilState(engine.noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        e.setRenderPipelineState(engine.browStripPipeline);e.setVertexBuffer(vb,offset:0,index:0)
        e.setFragmentBytes(&space,length:MemoryLayout<SIMD4<Float>>.stride,index:2);e.setFragmentTexture(fill,index:4)
        // Hide mask: fully hidden everywhere (all ones), so the fixture tests the composite, not the area.
        guard let hide=d.makeTexture(descriptor:fillDescriptor) else {throw CocoaError(.featureUnsupported)}
        let ones=Array(repeating:one,count:64)
        for slice in 0..<2 {ones.withUnsafeBytes {hide.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,slice:slice,withBytes:$0.baseAddress!,bytesPerRow:32,bytesPerImage:128)}}
        e.setFragmentTexture(hide,index:5)
        e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentBytes(&extent,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
        e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1);e.setFragmentTexture(brow,index:2);e.setFragmentTexture(mask,index:3)
        e.drawIndexedPrimitives(type:.triangle,indexCount:tris.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var data=Data(count:n*n*4);data.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*4,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return data
    }
    /// The production 3D hair pipeline over a flat face 30 cm from the camera: the brow mesh on it, an occluding patch of the face
    /// nearer to the camera when `occluderInFront`, and the face-skin mask covering everything when `handCovers`. Returns the
    /// target's BGRA pixels (128 x 128) over a mid-grey frame.
    static func renderBrowHairFixture(intensity:Float=1,occluderInFront:Bool=false,handCovers:Bool=false)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=128
        guard let mesh=BrowHairMesh.load() else {throw CocoaError(.fileNoSuchFile)}
        engine.installHairMesh(mesh)
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let mask=try texture(.r8Unorm,Array(repeating:handCovers ? 255:0,count:n*n),n)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        // The face: a flat patch at the head's depth, or in front of the brow by 2 cm.
        let depth:Float=occluderInFront ? 0.02:-0.01
        let patch:[SIMD3<Float>]=[.init(-0.06,-0.02,depth),.init(0.06,-0.02,depth),.init(0.06,0.07,depth),.init(-0.06,0.07,depth)]
        var faceToWorld=matrix_identity_float4x4;faceToWorld.columns.3=SIMD4(0,0,-0.3,1)
        let face=BrowFaceFrame(anchorID:UUID(),vertices:patch,triangles:[0,1,2,0,2,3],intrinsics:matrix_identity_float3x3,imageSize:SIMD2(1,1),faceToWorld:faceToWorld,cameraToWorld:matrix_identity_float4x4)
        guard engine.uploadFaceMesh(face,slot:0) else {throw CocoaError(.featureUnsupported)}
        guard let placement=BrowHairPlacement.frame(mesh:mesh,head:SIMD3(-0.027,0.02,0),tail:SIMD3(0.027,0.02,0),normal:SIMD3(0,0,1),forehead:SIMD3(0,1,0)) else {throw CocoaError(.coderInvalidValue)}
        // A Metal-style perspective: 0.05 m either side of the axis at 0.3 m fills the frame.
        let (near,far,scale):(Float,Float,Float)=(0.001,10,6)
        let projection=simd_float4x4(columns:(SIMD4(scale,0,0,0),SIMD4(0,scale,0,0),SIMD4(0,0,far/(near-far),-1),SIMD4(0,0,far*near/(near-far),0)))
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.05,0.03,0.02,intensity),controls:.zero,
                       tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,1),stretch:.zero)
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0.5,0.5,0.5,1)
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        engine.encodeHair(e,draws:[HairDraw(matrix:placement.matrix,scale:placement.scale,probe:SIMD2(0,0.02))],mvp:projection*faceToWorld,projectionScaleY:scale,
                          size:CGSize(width:n,height:n),light:1,uniforms:u,obstruction:mask,slot:0)
        e.endEncoding();command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var data=Data(count:n*n*4);data.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*4,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return data
    }
    /// The tracking view's mark vertex count and point labels for a synthetic observation.
    static func browTrackingFixture(_ observation:BrowObservation)->(vertices:Int,labels:[String]) {
        (browTrackingMarks(observation,raw:observation,display:.identity,size:CGSize(width:390,height:844),tracked:true).count,
         browTrackingLabels(observation,display:.identity).map(\.text))
    }
    /// Runs the eraser on a synthetic camera: bright skin, and dark brow hair around the subject's right brow that
    /// reaches `hairAbove` brow widths above its centerline. Returns the hide mask there at `w` (u = 0.5).
    static func browHideFixture(_ observation:BrowObservation,hairAbove:Float,w:Float)throws->Float {
        let engine=try BeautyBlushEngine(),d=engine.device
        guard let eraser=engine.eraser,let strip=browStrip(observation,display:.identity),let right=observation.brows[.subjectRight],
              let g0=BrowGeometry(contour:right) else {throw CocoaError(.featureUnsupported)}
        let left=observation.brows[.subjectLeft].flatMap {BrowGeometry(contour:$0)}
        guard let g=BrowGeometry(contour:right,across:max(g0.width,left?.width ?? 0)) else {throw CocoaError(.featureUnsupported)}
        let width=250,height=200,image=SIMD2(Float(observation.imageSize.width),Float(observation.imageSize.height))
        var luma=[UInt8](repeating:200,count:width*height)
        for u in stride(from:Float(0),through:1,by:0.01) {
            for across in stride(from:-g.observedHalf(u),through:hairAbove,by:0.01) {
                let p=g.point(u:u,w:across)/image
                let x=Int(p.x*Float(width)),y=Int(p.y*Float(height))
                if (0..<width).contains(x),(0..<height).contains(y) {luma[y*width+x]=40}
            }
        }
        func texture(_ format:MTLPixelFormat,_ w:Int,_ h:Int,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:w,height:h,mipmapped:false);desc.usage = .shaderRead;desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,width,height,luma,width),cb=try texture(.rg8Unorm,width/2,height/2,Array(repeating:128,count:width*height/2),width)
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:.zero,controls:.zero,tracking:.zero,camera:SIMD4(1,1,0,1),stretch:.zero)
        guard let command=engine.commands.makeCommandBuffer() else {throw CocoaError(.featureUnsupported)}
        eraser.encode(vertices:strip.unwrap,cropToRaw:nil,uniforms:withUnsafeBytes(of:&u) {Array($0)},y:y,cb:cb,timestamp:1,command:command)
        command.commit();command.waitUntilCompleted()
        if let error=command.error {throw error}
        return try eraser.hideFixture(u:0.5,w:w,slice:0,commands:engine.commands)
    }
    /// Strip vertices for a synthetic observation, as the renderer builds them.
    static func browStripFixture(_ observation:BrowObservation)->[(position:SIMD4<Float>,brow:SIMD4<Float>)]? {
        browStrip(observation,display:.identity)?.vertices.map {($0.position,$0.brow)}
    }
    /// Lower edge of the hidden-brow area per strip column of the subject's right brow, as (core, end) in brow widths.
    static func browConcealLowerFixture(_ observation:BrowObservation)->[SIMD2<Float>]? {
        browStrip(observation,display:.identity)?.vertices.prefix(browColumns+1).map {SIMD2($0.conceal.x,$0.conceal.y)}
    }
}
#endif
