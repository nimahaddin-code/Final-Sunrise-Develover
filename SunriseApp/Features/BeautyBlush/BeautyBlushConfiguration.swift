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
    let min_cutoff_hz:Double
    let velocity_beta:Double
    let visibility_tau_seconds:Double
    let mask_max_age_seconds:Double
    let max_yaw_degrees:Float
    let stretch_fade:[Float]
    let target_fps:Int
    let thermal_fps:Int
    static func load() throws->Self {
        guard let url=Bundle.main.url(forResource:"blush-rendering",withExtension:"json") else { throw CocoaError(.fileNoSuchFile) }
        return try decode(Data(contentsOf:url))
    }
    static func decode(_ data:Data)throws->Self {
        guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(object.keys)==Set(["mask_asset","atlas_size","paint_feather","coverage","absorption","saturation","pigment_mix","min_cutoff_hz","velocity_beta","visibility_tau_seconds","mask_max_age_seconds","max_yaw_degrees","stretch_fade","target_fps","thermal_fps"]) else{throw CocoaError(.coderInvalidValue)}
        let c=try JSONDecoder().decode(Self.self,from:data)
        guard c.paint_feather.isFinite,(0.2...1).contains(c.paint_feather),c.mask_asset=="blush-wash-mask.png",[512,1024].contains(c.atlas_size),
              [c.coverage,c.saturation,c.pigment_mix].allSatisfy({$0.isFinite && (0...1).contains($0)}),
              c.absorption.isFinite,(0...2).contains(c.absorption),
              c.min_cutoff_hz.isFinite,(2...30).contains(c.min_cutoff_hz),
              c.velocity_beta.isFinite,(0...200).contains(c.velocity_beta),
              c.visibility_tau_seconds.isFinite,(0.01...0.2).contains(c.visibility_tau_seconds),
              c.mask_max_age_seconds.isFinite,(0.03...0.3).contains(c.mask_max_age_seconds),
              c.max_yaw_degrees.isFinite,(30...85).contains(c.max_yaw_degrees),
              c.stretch_fade.count==4,c.stretch_fade.allSatisfy({$0.isFinite && $0>0 && $0<=3}),
              zip(c.stretch_fade,c.stretch_fade.dropFirst()).allSatisfy({$0<$1}),
              (30...60).contains(c.target_fps),(15...30).contains(c.thermal_fps) else { throw CocoaError(.coderInvalidValue) }
        return c
    }
    static func linear(_ c:Float)->Float { c<=0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
}
// Timestamp rejects backwards samples, keeps rigid ARKit pose unfiltered; only local mesh residuals are smoothed.
struct BeautyBlushVisibility {
    private(set) var value:Double=0
    private var timestamp:Double?
    mutating func update(timestamp t:Double,visible:Bool,tau:Double)->Double {
        guard t.isFinite else {return 0}
        guard let last=timestamp else {timestamp=t;return value}
        guard t>last else {return value}
        let dt=t-last;timestamp=t
        if dt>0.5 {value=0}
        let target:Double=visible ? 1:0
        value+=(target-value)*(1-exp(-min(dt,0.1)/tau))
        return value
    }
}

// Runtime Metal compiler is part of iOS; compile once off the main thread. No downloaded compiler dependency.
@preconcurrency import Metal
private enum BeautyBlushShaderError:Error {case missingSource}
enum BeautyBlushShaders {
    static let library:MTLLibrary? = {
        guard let device=MTLCreateSystemDefaultDevice(),let url=Bundle.main.url(forResource:"BeautyBlush.metal",withExtension:"txt"),let source=try? String(contentsOf:url,encoding:.utf8) else{return nil}
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
