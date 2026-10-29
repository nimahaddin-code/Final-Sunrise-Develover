// -Nimah: Rendering/tracking settings are separate from aesthetic placement presets.
import Foundation
import simd
struct BeautyBlushConfiguration:Decodable,Sendable {
    let mask_asset:String
    let atlas_size:Int
    let paint_feather:Float
    let coverage:Float
    let absorption:Float
    let saturation:Float
    let pigment_mix:Float
    /// Radius, in camera pixels, of the low-frequency skin the pigment colours; finer detail is kept from the camera.
    let detail_radius_px:Float
    let min_cutoff_hz:Double
    let velocity_beta:Double
    let visibility_tau_seconds:Double
    let mask_max_age_seconds:Double
    let mask_fade_seconds:Double
    let max_yaw_degrees:Float
    let stretch_fade:[Float]
    let target_fps:Int
    let thermal_fps:Int
    static func load() throws->Self {
        guard let url=Bundle.main.url(forResource:"blush-rendering",withExtension:"json") else { throw CocoaError(.fileNoSuchFile) }
        return try decode(Data(contentsOf:url))
    }
    static func decode(_ data:Data)throws->Self {
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(object.keys)==Set(["mask_asset","atlas_size","paint_feather","coverage","absorption","saturation","pigment_mix","detail_radius_px","min_cutoff_hz","velocity_beta","visibility_tau_seconds","mask_max_age_seconds","mask_fade_seconds","max_yaw_degrees","stretch_fade","target_fps","thermal_fps"]) else{throw CocoaError(.coderInvalidValue)}
        let c=try JSONDecoder().decode(Self.self,from:data)
        guard c.paint_feather.isFinite,(0.2...1).contains(c.paint_feather),c.mask_asset=="blush-wash-mask.png",[512,1024].contains(c.atlas_size),
              [c.coverage,c.saturation,c.pigment_mix].allSatisfy({$0.isFinite && (0...1).contains($0)}),
              c.absorption.isFinite,(0...2).contains(c.absorption),
              c.detail_radius_px.isFinite,(2...16).contains(c.detail_radius_px),
              c.min_cutoff_hz.isFinite,(2...30).contains(c.min_cutoff_hz),
              c.velocity_beta.isFinite,(0...200).contains(c.velocity_beta),
              c.visibility_tau_seconds.isFinite,(0.01...0.2).contains(c.visibility_tau_seconds),
              c.mask_max_age_seconds.isFinite,(0.03...0.3).contains(c.mask_max_age_seconds),
              c.mask_fade_seconds.isFinite,(0.03...0.15).contains(c.mask_fade_seconds),
              c.max_yaw_degrees.isFinite,(30...85).contains(c.max_yaw_degrees),
              c.stretch_fade.count==4,c.stretch_fade.allSatisfy({$0.isFinite && $0>0 && $0<=3}),
              zip(c.stretch_fade,c.stretch_fade.dropFirst()).allSatisfy({$0<$1}),
              (30...60).contains(c.target_fps),(15...30).contains(c.thermal_fps) else { throw CocoaError(.coderInvalidValue) }
        return c
    }
    // -Nimah: Keep cosmetic surface within 0.25 mm of the current expression mesh, avoiding sliding.
    static func limitResidual(filtered:SIMD3<Float>,current:SIMD3<Float>)->SIMD3<Float> {
        let delta=filtered-current,distance=simd_length(delta)
        return distance>0.00025 ? current+delta*(0.00025/distance):filtered
    }
    static func linear(_ c:Float)->Float { c<=0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
}
// Timestamp rejects backwards samples, keeps rigid ARKit pose unfiltered; only local mesh residuals are smoothed.
struct BeautyBlushVisibility {
    private(set) var value:Double=0
    private var timestamp:Double?
    mutating func update(timestamp t:Double,visible:Bool,tau:Double)->Double {
        update(timestamp:t,target:visible ? 1:0,tau:tau)
    }
    mutating func update(timestamp t:Double,target requested:Double,tau:Double)->Double {
        guard t.isFinite else {return 0}
        guard let last=timestamp else {timestamp=t;return value}
        guard t>last else {return value}
        let dt=t-last;timestamp=t
        if dt>0.5 {value=0}
        let target=max(0,min(1,requested))
        value+=(target-value)*(1-exp(-min(dt,0.1)/tau))
        return value
    }
}

// Runtime Metal compiler is part of iOS; compile once off the main thread. No downloaded compiler dependency.
@preconcurrency import Metal
private enum BeautyBlushShaderError:Error {case missingSource}
enum BeautyBlushShaders {
    /// Shader sources compiled as one library, in order: the shared camera/blush code, then the brow code that uses it.
    static let sources=["BeautyBlush.metal","Brow.metal"]
    static let library:MTLLibrary? = {
        let parts=sources.map {Bundle.main.url(forResource:$0,withExtension:"txt").flatMap {try? String(contentsOf:$0,encoding:.utf8)}}
        guard let device=MTLCreateSystemDefaultDevice(),parts.allSatisfy({$0 != nil}) else{return nil}
        let source=parts.compactMap {$0}.joined(separator:"\n")
        do {return try device.makeLibrary(source:source,options:nil)} catch {
            UserDefaults.standard.set("shader_compile: \(error)",forKey:"beautyBlush.status");return nil
        }
    }()
}

// -Nimah: Metre-space brow residual smoothing. Rigid ARKit pose remains current and unfiltered.
struct BeautyBrowStabilizer {
    private var axes=[OneEuroFilter(),OneEuroFilter(),OneEuroFilter()]
    private var output:SIMD3<Float>?
    private var time:Double?
    mutating func update(_ point:SIMD3<Float>,timestamp:Double)->SIMD3<Float> {
        guard timestamp.isFinite,point.x.isFinite,point.y.isFinite,point.z.isFinite else {return output ?? .zero}
        if let time,timestamp<=time {return output ?? point}
        if let time,timestamp-time>0.15 {axes=[OneEuroFilter(),OneEuroFilter(),OneEuroFilter()];output=nil}
        time=timestamp
        let config=OneEuroConfig(minCutoff:2,beta:80,dCutoff:1,deadband:0)
        var filtered=point
        for i in 0..<3 {filtered[i]=Float(axes[i].filter(Double(point[i]),t:timestamp,config:config))}
        // 0.12 mm local residual hold; accumulated movement eventually exits the band.
        if let output,simd_distance(output,filtered)<0.00012 {return output}
        output=filtered;return filtered
    }
}

// -Nimah: Soft expiry avoids an all-or-nothing flash between segmentation deliveries.
// Freshness is unchanged; only a bounded fade/reprojection window is permitted before fully hiding.
enum BeautyMaskContinuity {
    // The filtered recovery must not be bypassed by a newly delivered (younger) mask.
    // Reserve the final half of the grace window for a strict, smooth expiry ceiling.
    static func opacity(filtered:Double,age:Double,freshAge:Double,fadeSeconds:Double)->Double {
        guard filtered.isFinite else {return 0}
        let ceiling=weight(age:age,freshAge:freshAge+fadeSeconds*0.5,fadeSeconds:fadeSeconds*0.5)
        return min(max(0,min(1,filtered)),ceiling)
    }
    static func weight(age:Double,freshAge:Double,fadeSeconds:Double)->Double {
        guard age.isFinite,age>=0,freshAge>0,fadeSeconds>0 else {return 0}
        let t=max(0,min(1,(age-freshAge)/fadeSeconds))
        return 1-t*t*(3-2*t)
    }
}

// Developer-only blush comparison switches (developer tools on, blush selected). Same camera frame, mask and alpha
// for every choice, so differences are the blend itself. Users always get `.pigment` / `.final`.
enum BlushBlend:Int,CaseIterable,Identifiable {
    case pigment,legacy,alpha,multiply,softLight
    var id:Int {rawValue}
    var title:String {switch self {
    case .pigment:"Skin-preserving pigment";case .legacy:"Previous blend";case .alpha:"Linear alpha"
    case .multiply:"Multiply";case .softLight:"Soft light"}}
}
enum BlushDiagnostic:Int,CaseIterable,Identifiable {
    case final,neutral,uvChecker,mask,boundaries,visibility,wireframe
    var id:Int {rawValue}
    var title:String {switch self {
    case .final:"Final";case .neutral:"Neutral geometry";case .uvChecker:"UV checker";case .mask:"Pigment mask"
    case .boundaries:"Mask boundaries";case .visibility:"Visibility (R occluded, G stretch, B tracking)";case .wireframe:"Triangle wireframe"}}
    /// The wireframe is an extra pass over the final picture, not a shader view.
    var shaderValue:Int {self == .wireframe ? 0:rawValue}
}
