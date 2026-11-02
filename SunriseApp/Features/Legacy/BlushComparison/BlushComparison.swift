import Foundation
import ARKit
import SwiftUI
import simd

enum BlushBackend:Int,CaseIterable,Identifiable {
    case arkit,mediapipe,banuba,byteplus
    var id:Int {rawValue}
    var title:String {switch self {case .arkit:"ARKit + Metal";case .mediapipe:"MediaPipe + Metal (comparison)";case .banuba:"Banuba — unavailable";case .byteplus:"BytePlus — unavailable"}}
    var available:Bool {self == .arkit || self == .mediapipe}
    var missingDependency:String? {switch self {
    case .banuba:"Banuba Face AR iOS package, valid client token with Advanced Makeup entitlement, and licensed custom effect assets are not installed."
    case .byteplus:"BytePlus Effects iOS SDK package, matching models/materials, and unexpired offline license for com.sunrise.foundation are not installed."
    default:nil
    }}
    static let key="beautyBlush.backend"
}
enum BlushBlend:Int,CaseIterable,Identifiable {
    case legacy,pigment,alpha,multiply,softLight
    var id:Int {rawValue}
    var title:String {switch self {case .legacy:"Existing blend";case .pigment:"Skin luminance pigment";case .alpha:"Linear alpha";case .multiply:"Multiply";case .softLight:"Soft light"}}
    static let key="beautyBlush.blend"
}
enum BlushDiagnostic:Int,CaseIterable,Identifiable {
    case final,neutral,wireframe,uv,mask,visibility,landmarks,boundaries
    var id:Int {rawValue}
    var title:String {switch self {case .final:"Final";case .neutral:"Neutral pigment";case .wireframe:"Triangle wireframe";case .uv:"UV checker";case .mask:"Pigment mask";case .visibility:"Surface visibility";case .landmarks:"Landmark indices";case .boundaries:"Mask boundaries"}}
    static let key="beautyBlush.diagnostic"
}
struct BlushDeveloperMenu:View {
    @AppStorage(BlushBackend.key) private var backend=0
    @AppStorage(BlushBlend.key) private var blend=1
    @AppStorage(BlushDiagnostic.key) private var diagnostic=0
    @AppStorage("beautyBlush.freeze") private var frozen=false
    var body:some View {
        Menu {
            Picker("Blush tracker",selection:$backend) {ForEach(BlushBackend.allCases) {Text($0.title).tag($0.rawValue).disabled(!$0.available)}}
            Picker("Blending on the same frame",selection:$blend) {ForEach(BlushBlend.allCases) {Text($0.title).tag($0.rawValue)}}
            Picker("Diagnostic",selection:$diagnostic) {ForEach(BlushDiagnostic.allCases) {Text($0.title).tag($0.rawValue)}}
            Toggle("Freeze source frame (memory only)",isOn:$frozen)
            Text("Commercial SDKs need packages, matching licensed effects and credentials. No camera image is saved.")
        } label: {
            Label("Blush lab",systemImage:"ladybug").font(.caption).padding(10)
                .background(AppColors.cocoa.opacity(0.9),in:Capsule()).foregroundStyle(.white)
        }
    }
}

/// Provider-specific vertex/UV indices. Never share this topology with ARFaceGeometry.
struct MediaPipeBlushTopology:Decodable,Sendable {
    let source:String
    let sha256:String
    let vertices:[[Float]]
    let uv:[[Float]]
    let faces:[[[Int]]]
    let excludedVertices:[Int]
    var canonical:[SIMD3<Float>] {vertices.map {SIMD3($0[0],$0[1],$0[2])}}
    var corners:[(Int,Int)] {faces.flatMap {$0.map {($0[0],$0[1])}}}
    var skinCorners:[(Int,Int)] {let blocked=Set(excludedVertices);return faces.filter {!$0.contains {blocked.contains($0[0])}}.flatMap {$0.map {($0[0],$0[1])}}}
    static func load()throws->Self {
        guard let url=Bundle.main.url(forResource:"mediapipe-canonical-face",withExtension:"json") else {throw CocoaError(.fileNoSuchFile)}
        let result=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard result.vertices.count==468,result.vertices.allSatisfy({$0.count==3 && $0.allSatisfy(\.isFinite)}),result.uv.allSatisfy({$0.count==2 && $0.allSatisfy {$0.isFinite && (0...1).contains($0)}}),
              result.faces.allSatisfy({$0.count==3 && $0.allSatisfy {$0.count==2 && result.vertices.indices.contains($0[0]) && result.uv.indices.contains($0[1])}}) else {throw CocoaError(.coderInvalidValue)}
        return result
    }
}

struct MediaPipeBlushSurface {
    let local:[SIMD3<Float>]
    let region:EyebrowRegion
    /// 2D eye-aligned coordinates normalized to a canonical 64 mm interocular span.
    /// These are template-scaled fitting coordinates, NOT estimated physical measurements.
    static func make(_ o:BrowObservation,topology:MediaPipeBlushTopology,id:UUID)->Self? {
        guard o.mesh.count>=topology.vertices.count,o.mesh.prefix(468).allSatisfy({$0.x.isFinite && $0.y.isFinite}),o.normalizedDepth.prefix(468).allSatisfy(\.isFinite),let re=o.eyes[.subjectRight],let le=o.eyes[.subjectLeft] else {return nil}
        let r=(re.inner+re.outer)/2,l=(le.inner+le.outer)/2,span=simd_distance(r,l)
        guard span>8 else{return nil}
        let origin=(l+r)/2,x=(l-r)/span
        var y=SIMD2(-x.y,x.x)
        if simd_dot((re.ala+le.ala)/2-origin,y)>0 {y = -y}
        let canonical=topology.canonical,eyeZ=(canonical[33].z+canonical[263].z)/2
        func convert(_ p:SIMD2<Float>,z:Float)->SIMD3<Float> {let d=(p-origin)*(0.064/span);return SIMD3(simd_dot(d,x),simd_dot(d,y),z-eyeZ)}
        let points=(0..<468).map {convert(o.mesh[$0],z:canonical[$0].z)}
        let triangles=topology.faces.flatMap {$0.map {Int16($0[0])}}
        func attachment(_ i:Int)->SurfaceAttachment? {
            for f in topology.faces {let ids=f.map {$0[0]};if let corner=ids.firstIndex(of:i) {var w=SIMD3<Float>.zero;w[corner]=1;return SurfaceAttachment(indices:SIMD3(ids[0],ids[1],ids[2]),weights:w)}}
            return nil
        }
        let maps=[MediaPipeEyeLandmarkProvider.subjectRightMap,MediaPipeEyeLandmarkProvider.subjectLeftMap]
        let eyes=[convert(r,z:eyeZ),convert(l,z:eyeZ)]
        let brows=maps.enumerated().map {index,m in
            let e=index==0 ? re:le,eye=eyes[index]
            let ala=convert(e.ala,z:canonical[98].z),outer=convert(e.outer,z:eyeZ)
            let landmarks=m.browUpper.compactMap(attachment)
            return EyebrowRegion.Brow(side:index==0 ? .right:.left,landmarks:landmarks,mapping:.init(ala:ala,pupil:eye,outerEye:outer,start:.zero,arch:.zero,tail:.zero))
        }
        let region=EyebrowRegion(brows:brows,faceObservationConfidence:0,timestamp:o.timestamp,anchorID:id,restVertices:points,triangles:triangles,eyeCenters:eyes)
        return .init(local:points,region:region)
    }
}

/// Owned by the lab only. Never encoded, written to disk, or uploaded.
/// ARKit cannot infer a new ARFaceAnchor from arbitrary recorded images: cross-tracker
/// frozen comparison is therefore supported ARKit → MediaPipe, not the reverse.
final class BlushComparisonFrameStore:@unchecked Sendable {
    static let shared=BlushComparisonFrameStore()
    private let lock=NSLock()
    private var saved:(ARFrame,BlushCameraSample,OcclusionMask?)?
    func save(_ frame:ARFrame,display:CGAffineTransform,mask:OcclusionMask?,epoch:UUID) {
        lock.lock();defer {lock.unlock()}
        guard saved==nil else{return}
        saved=(frame,.init(capturedImage:frame.capturedImage,timestamp:frame.timestamp,display:display,epoch:epoch),mask)
    }
    func read()->(ARFrame,BlushCameraSample,OcclusionMask?)? {lock.lock();defer {lock.unlock()};return saved}
    func clear() {lock.lock();saved=nil;lock.unlock()}
}

/// Scalar run summary. No image, landmark, demographic or identity data.
struct BlushRunStatistics {
    private var start:Double?
    private var frames=0,visibleFrames=0,thermalPeak=0
    private var gpuPeak:Double=0,agePeak:Double=0
    mutating func record(startTime:Double,time:Double,completed:Int,visible:Int,gpuMax:Double,ageP95:Double,thermal:Int)->[String:Double] {
        if start==nil {start=startTime}
        frames += completed;visibleFrames += visible;thermalPeak=max(thermalPeak,thermal)
        gpuPeak=max(gpuPeak,gpuMax);agePeak=max(agePeak,ageP95)
        let duration=max(0.001,time-(start ?? time))
        return ["run_seconds":duration,"run_completed_frames":Double(frames),"run_fps_completed":Double(frames)/duration,"run_visible_frames":Double(visibleFrames),"run_thermal_peak":Double(thermalPeak),"run_gpu_ms_max":gpuPeak,"run_frame_age_p95_max":agePeak]
    }
}
