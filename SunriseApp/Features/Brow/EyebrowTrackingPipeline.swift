// -Nimah: Shared brow/forehead mapping; satu worker, satu frame buffer dan epoch/anchor guard.
import ARKit

final class EyebrowTrackingPipeline: @unchecked Sendable {
    struct Snapshot: Sendable {
        let guide:EyebrowGuide?
        let foreheadGuide:ForeheadGuide?
        let message:String
        let confidence:Float?
        var blushGuide:BlushPlacementGuide? = nil
        var ready:Bool { guide != nil || foreheadGuide != nil || blushGuide != nil }
    }
    private let lock=NSLock()
    private let worker=DispatchQueue(label:"sunrise.eyebrow-vision",qos:.userInitiated)
    private let provider:any FaceLandmarkProviding
    private var ticket=UUID(),anchorID:UUID?
    private var region:EyebrowRegion?,guide:EyebrowGuide?,forehead:ForeheadGuide?
    private var blush:BlushPlacementGuide?,blushAttempt:BlushPlacementStyle?
    private var foreheadAttempt:String?
    private let requiredScanSamples:Int
    private var scanCandidate:EyebrowRegion?,scanCount=0
    private var wasTracked=false,busy=false,lastAttempt:TimeInterval=0
    private var lostSince:TimeInterval?
    private var message="Face the camera with eyebrows visible"
    init(provider:any FaceLandmarkProviding = VisionFaceLandmarkProvider(),requiredScanSamples:Int = 3) { self.provider=provider; self.requiredScanSamples=max(1,requiredScanSamples) }
    func reset(anchorID:UUID? = nil) {
        lock.lock(); defer { lock.unlock() }
        lostSince=nil; ticket=UUID(); self.anchorID=anchorID; region=nil; guide=nil; forehead=nil; foreheadAttempt=nil; blush=nil; blushAttempt=nil
        busy=false; wasTracked=false; scanCandidate=nil; scanCount=0; lastAttempt=0; message="Hold still with both eyebrows visible"
    }
    // -Nimah: Hide immediately, retain same-anchor calibration for a brief dropout only.
    func trackingLost(timestamp:TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        if lostSince==nil { lostSince=timestamp }
        wasTracked=false
        guard timestamp-(lostSince ?? timestamp)>=1 else { message="Tracking interrupted · face the camera to resume"; return }
        busy=false; scanCandidate=nil; scanCount=0; ticket=UUID(); region=nil; guide=nil; forehead=nil; foreheadAttempt=nil; blush=nil; blushAttempt=nil; lastAttempt=0
        message="Tracking lost · scanning again automatically"
    }
    // -Nimah: Same-anchor recovery resumes cached calibration without another Vision scan.
    func resumeTracking(anchorID:UUID) {
        lock.lock(); defer { lock.unlock() }
        guard self.anchorID==anchorID else { return }
        wasTracked=true; lostSince=nil
    }
    // -Nimah: No Vision scan, sample accumulation, head-pose or hold-still gate in try-on.
    func followLaunchFit(anchorID:UUID,vertices:[SIMD3<Float>],triangles:[Int16],timestamp:TimeInterval,
                         style:EyebrowStyle,blushStyle:BlushPlacementStyle?,eyeCenters:[SIMD3<Float>] = [],cache:LaunchMakeupFit = .shared) {
        resumeTracking(anchorID:anchorID)
        // Without a launch fit (scan skipped or failed) there is nothing to attach: stop here instead of failing and
        // reporting the same error on every camera frame.
        guard cache.hasFit else { return }
        lock.lock()
        guard self.anchorID==anchorID,!busy else { lock.unlock();return }
        guard region==nil || guide?.style != style || blush?.style != blushStyle else { lock.unlock();return }
        let token=ticket;busy=true;lock.unlock()
        guard let fitted=cache.fittedRegion(anchorID:anchorID,vertices:vertices,triangles:triangles,timestamp:timestamp,eyeCenters:eyeCenters) else {
            complete(token:token,id:anchorID,region:nil,guide:nil,errorMessage:"Look straight at the camera to place your makeup")
            return
        }
        worker.async {
            self.complete(token:token,id:anchorID,region:fitted,guide:EyebrowGuideGenerator.make(region:fitted,style:style),
                blush:blushStyle.flatMap { BlushPlacementGenerator.make(region:fitted,style:$0) },blushRequested:blushStyle != nil)
        }
    }
    private func key(_ style:ForeheadStyle,_ height:Float) -> String { style.rawValue+"-\(max(0.45,min(1,height)))" }
    func snapshot(style:EyebrowStyle,foreheadStyle:ForeheadStyle? = nil,height:Float = 0.8,includeBrow:Bool = false,blushStyle:BlushPlacementStyle? = nil) -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        guard wasTracked else { return Snapshot(guide:nil,foreheadGuide:nil,message:message,confidence:nil) }
        if let blushStyle {
            let valid=blush?.style==blushStyle
            return Snapshot(guide:includeBrow && guide?.style==style ? guide : nil,foreheadGuide:nil,
                message:valid ? "Blush mapped · check cheek placement" : message,confidence:region?.faceObservationConfidence,blushGuide:valid ? blush : nil)
        }
        if let foreheadStyle {
            let valid=forehead?.style==foreheadStyle && forehead?.height==max(0.45,min(1,height))
            return Snapshot(guide:includeBrow && guide?.style==style ? guide : nil,foreheadGuide:valid ? forehead : nil,message:valid ? "Forehead guide ready · check top edge within visible skin" : message,
                confidence:region?.faceObservationConfidence)
        }
        return Snapshot(guide:guide?.style==style ? guide : nil,foreheadGuide:nil,message:guide?.style==style ? "Brow shape ready" : message,
            confidence:region?.faceObservationConfidence)
    }
    func observe(frame:ARFrame,anchor:ARFaceAnchor,canCalibrate:Bool,style:EyebrowStyle,foreheadStyle:ForeheadStyle? = nil,height:Float = 0.8,blushStyle:BlushPlacementStyle? = nil) {
        // -Nimah: Eye scan requires eyes open; blinking must not calibrate inaccurate pupils.
        let blink=max(anchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0,anchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0)
        resumeTracking(anchorID:anchor.identifier)
        lock.lock()
        if region==nil && blink>0.25 { scanCandidate=nil; scanCount=0; message="Open both eyes and look at the camera"; lock.unlock(); return }
        guard anchorID==anchor.identifier,!busy else { lock.unlock(); return }
        let token=ticket,id=anchor.identifier
        let needForehead=foreheadStyle.map { foreheadAttempt != key($0,height) || (forehead == nil && frame.timestamp-lastAttempt>0.75) } ?? false
        let needBlush=blushStyle.map { blushAttempt != $0 || (blush == nil && frame.timestamp-lastAttempt>0.75) } ?? false
        if let region,guide?.style != style || needForehead || needBlush {
            // -Nimah: Failed placement is retried with a cooldown, rather than cached forever.
            busy=true; lastAttempt=frame.timestamp; message="Updating placement guide"
            if let foreheadStyle { foreheadAttempt=key(foreheadStyle,height) }
            if let blushStyle { blushAttempt=blushStyle }
            lock.unlock()
            worker.async {
                let brow=EyebrowGuideGenerator.make(region:region,style:style)
                let area=foreheadStyle.flatMap { ForeheadGuideGenerator.make(region:region,style:$0,height:height) }
                self.complete(token:token,id:id,region:region,guide:brow,forehead:area,foreheadRequested:foreheadStyle != nil,blush:blushStyle.flatMap { BlushPlacementGenerator.make(region:region,style:$0) },blushRequested:blushStyle != nil)
            }
            return
        }
        guard region==nil,canCalibrate,frame.timestamp-lastAttempt>0.75 else { lock.unlock(); return }
        lock.unlock()
        calibrate(input:FaceLandmarkFrame(frame:frame,anchor:anchor),style:style,foreheadStyle:foreheadStyle,height:height,blushStyle:blushStyle)
    }
    func calibrate(input:FaceLandmarkFrame,style:EyebrowStyle,foreheadStyle:ForeheadStyle? = nil,height:Float = 0.8,blushStyle:BlushPlacementStyle? = nil) {
        lock.lock()
        guard input.anchorID==anchorID,!busy else { lock.unlock(); return }
        // -Nimah: The pupil depth-plane approximation is calibrated only near frontal pose (~20 degrees).
        guard input.projection.cameraFromFace.columns.2.z>0.94 else {
            scanCandidate=nil; scanCount=0; message="Face forward for the eye scan"; lock.unlock(); return
        }
        let token=ticket,id=input.anchorID
        if let foreheadStyle { foreheadAttempt=key(foreheadStyle,height) }
        if let blushStyle { blushAttempt=blushStyle }
        wasTracked=true; lostSince=nil; busy=true; lastAttempt=input.timestamp; message="Scanning eyes, pupils and nose"; lock.unlock()
        worker.async {
            let detected:[DetectedEyebrows]
            do { detected=try self.provider.detectEyebrows(in:input) }
            catch {
                self.complete(token:token,id:id,region:nil,guide:nil,errorMessage:"Face analysis unavailable · refit or retry camera")
                return
            }
            let mapped=detected.compactMap { candidate in
                EyebrowRegionMapper.map(candidate,projection:input.projection,vertices:input.vertices,triangles:input.triangles,
                    leftEye:input.leftEye,rightEye:input.rightEye,timestamp:input.timestamp,anchorID:input.anchorID)
            }.max { $0.faceObservationConfidence < $1.faceObservationConfidence }
            // -Nimah: Validate several independent observations; keep the latest real mesh, not averaged mesh indices.
            guard self.acceptScan(mapped,token:token,id:id) else { return }
            let brow=mapped.flatMap { EyebrowGuideGenerator.make(region:$0,style:style) }
            let area=mapped.flatMap { region in foreheadStyle.flatMap { ForeheadGuideGenerator.make(region:region,style:$0,height:height) } }
            self.complete(token:token,id:id,region:mapped,guide:brow,forehead:area,foreheadRequested:foreheadStyle != nil,blush:mapped.flatMap { r in blushStyle.flatMap { BlushPlacementGenerator.make(region:r,style:$0) } },blushRequested:blushStyle != nil)
        }
    }
    private func acceptScan(_ mapped:EyebrowRegion?,token:UUID,id:UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard ticket==token,anchorID==id else { return false }
        guard let mapped else {
            scanCandidate=nil; scanCount=0; busy=false
            message="Scan incomplete · show both eyes and nose, look straight at the camera"
            return false
        }
        let stable=scanCandidate.map { Self.consistent($0,mapped) } ?? false
        scanCount=stable ? scanCount+1 : 1; scanCandidate=mapped
        if scanCount<requiredScanSamples {
            busy=false; message="Eye scan \(scanCount)/\(requiredScanSamples) · keep looking straight"
            return false
        }
        return true
    }
    // -Nimah: Threshold is a prototype stability gate, not an accuracy score.
    static func consistent(_ a:EyebrowRegion,_ b:EyebrowRegion) -> Bool {
        guard a.anchorID==b.anchorID,b.timestamp>a.timestamp,b.timestamp-a.timestamp<=2 else { return false }
        for brow in a.brows {
            guard let x=brow.mapping,let y=b.brows.first(where:{ $0.side==brow.side })?.mapping else { return false }
            let width=abs(x.tail.x-x.start.x),tolerance=max(0.0008,width*0.045)
            for (p,q) in [(x.start,y.start),(x.arch,y.arch),(x.tail,y.tail)] {
                guard simd_distance(p,q)<tolerance else { return false }
            }
        }
        return a.brows.count==2 && b.brows.count==2
    }
    private func complete(token:UUID,id:UUID,region:EyebrowRegion?,guide:EyebrowGuide?,forehead:ForeheadGuide? = nil,
                          foreheadRequested:Bool = false,blush:BlushPlacementGuide? = nil,blushRequested:Bool = false,errorMessage:String? = nil) {
        lock.lock(); defer { lock.unlock() }
        // -Nimah: A cancelled worker must never unlock or overwrite the next scan.
        guard ticket==token,anchorID==id else { return }
        busy=false
        self.region=region; self.guide=guide; self.forehead=forehead; self.blush=blush
        if !blushRequested { blushAttempt=nil }
        if !foreheadRequested { foreheadAttempt=nil }
        if guide==nil {
            self.region=nil; foreheadAttempt=nil; self.blush=nil; blushAttempt=nil
            message=errorMessage ?? "Brows not mapped · face forward with both eyebrows visible"
        } else if blushRequested && blush==nil { message="Cheek placement unavailable on this mesh · refit with eyes and cheeks visible" }
        else if foreheadRequested && forehead==nil { message="Area outside tracked forehead · lower the top limit or refit" }
    }
}

// -Nimah: Transient brow/cheek fitting. No photo or mesh is written to disk.
// The shared fit comes from live try-on/tutorial frames (`fitLive`), not a launch scan, and is memory-only;
// try-on only reuses attachments on matching ARKit topology.
final class LaunchMakeupFit: @unchecked Sendable {
    static let shared:LaunchMakeupFit={
        // Sparse attachments saved by the removed launch scan are no longer used.
        UserDefaults.standard.removeObject(forKey:key);return LaunchMakeupFit()
    }()
    private let lock=NSLock()
    private var epoch=UUID()
    private var region:EyebrowRegion?
    // -Nimah: Persist only sparse fitting descriptors, never a frame, full mesh or triangle array.
    private struct SavedFit:Codable {
        let brows:[EyebrowRegion.Brow]
        let vertexCount:Int
        let triangleCount:Int
        let confidence:Float
        var eyeCenters:[SIMD3<Float>]? = nil
    }
    private static let key="savedMakeupAttachments.v1"
    private let defaults:UserDefaults?
    private var saved:SavedFit?
    private var lastStage="not_started"
    private let liveWorker=DispatchQueue(label:"sunrise.live-makeup-fit",qos:.userInitiated)
    private let liveProvider:any FaceLandmarkProviding=VisionFaceLandmarkProvider(requireEyeFormula:false)
    private var liveBusy=false,lastLiveAttempt:TimeInterval = -.infinity
    var diagnostic:String { lock.lock();defer { lock.unlock() };return lastStage }
    init(defaults:UserDefaults? = nil) {
        self.defaults=defaults
        saved=defaults?.data(forKey:Self.key).flatMap { try? JSONDecoder().decode(SavedFit.self,from:$0) }
        if saved?.brows.count != 2 { saved=nil }
    }
    var hasFit:Bool { lock.lock();defer { lock.unlock() };return region != nil || saved != nil }
    func clear() { lock.lock();epoch=UUID();region=nil;saved=nil;lastLiveAttempt = -.infinity;defaults?.removeObject(forKey:Self.key);lock.unlock() }
    // Fits from a live tracked frame until one succeeds: one Vision attempt at a time, at most every 0.4 s.
    func fitLive(_ input:FaceLandmarkFrame) {
        lock.lock()
        guard region==nil,saved==nil,!liveBusy,input.timestamp-lastLiveAttempt>=0.4 else { lock.unlock();return }
        liveBusy=true;lastLiveAttempt=input.timestamp;lock.unlock()
        liveWorker.async { [self] in
            _=prepare(input,provider:liveProvider)
            lock.lock();liveBusy=false;lock.unlock()
        }
    }
    func prepare(_ input:FaceLandmarkFrame,provider:any FaceLandmarkProviding = VisionFaceLandmarkProvider(requireEyeFormula:false))->Bool {
        lock.lock();let token=epoch;lock.unlock()
        // -Nimah: Match the scan module's supported sensor orientations during enrollment only.
        // Validate actual projected brow attachments before accepting a fallback; no guessed coordinates.
        var mapped:EyebrowRegion?
        var stage="landmarks_not_detected"
        let orientations=[input.orientation]+FaceContourDetector.orientations.filter { $0 != input.orientation }
        for orientation in orientations {
            guard !Task.isCancelled else { return false }
            let sample=FaceLandmarkFrame(pixelBuffer:input.pixelBuffer,projection:input.projection,orientation:orientation,
                timestamp:input.timestamp,anchorID:input.anchorID,vertices:input.vertices,triangles:input.triangles,
                leftEye:input.leftEye,rightEye:input.rightEye)
            guard let detected=try? provider.detectEyebrows(in:sample) else { continue }
            mapped=detected.compactMap { detection in
                EyebrowRegionMapper.map(detection,projection:sample.projection,vertices:sample.vertices,triangles:sample.triangles,
                    leftEye:sample.leftEye,rightEye:sample.rightEye,timestamp:sample.timestamp,anchorID:sample.anchorID,requireFormula:false,diagnostic:{ stage=$0 })
            }.filter {
                let valid=EyebrowGuideGenerator.make(region:$0,style:.softNatural) != nil
                if !valid { stage="guide_generation" };return valid
            }
                .max { $0.faceObservationConfidence < $1.faceObservationConfidence }
            if mapped != nil { break }
        }
        guard let mapped else { lock.lock();lastStage=stage;lock.unlock();return false }
        lock.lock();defer { lock.unlock() }
        guard epoch==token,!Task.isCancelled else { return false }
        region=mapped;lastStage="fit_ready"
        saved=SavedFit(brows:mapped.brows,vertexCount:mapped.restVertices.count,triangleCount:mapped.triangles.count,confidence:mapped.faceObservationConfidence,eyeCenters:mapped.eyeCenters)
        if let saved,let data=try? JSONEncoder().encode(saved) { defaults?.set(data,forKey:Self.key) }
        return true
    }
    // -Nimah: Commit a completed retake atomically; cancellation/failure keeps the previous saved fit.
    func replace(with candidate:LaunchMakeupFit)->Bool {
        candidate.lock.lock();let next=candidate.region,descriptor=candidate.saved;candidate.lock.unlock()
        guard let next,let descriptor else { return false }
        lock.lock();defer { lock.unlock() }
        epoch=UUID();region=next;saved=descriptor
        if let data=try? JSONEncoder().encode(descriptor) { defaults?.set(data,forKey:Self.key) }
        return true
    }
    func fittedRegion(anchorID:UUID,vertices:[SIMD3<Float>],triangles:[Int16],timestamp:TimeInterval,eyeCenters:[SIMD3<Float>] = [])->EyebrowRegion? {
        lock.lock();defer { lock.unlock() }
        if region==nil,let saved,saved.vertexCount==vertices.count,saved.triangleCount==triangles.count,
           saved.brows.allSatisfy({ $0.landmarks.count>=3 && $0.landmarks.allSatisfy { $0.position(in:vertices) != nil } }) {
            // -Nimah: Reattach stored barycentric brow anchors to the current live face; no classification or Vision scan.
            region=EyebrowRegion(brows:saved.brows,faceObservationConfidence:saved.confidence,timestamp:timestamp,
                anchorID:anchorID,restVertices:vertices,triangles:triangles,eyeCenters:saved.eyeCenters ?? eyeCenters)
        }
        guard let region,region.restVertices.count==vertices.count,region.triangles==triangles else { return nil }
        return EyebrowRegion(brows:region.brows,faceObservationConfidence:region.faceObservationConfidence,
            timestamp:timestamp,anchorID:anchorID,restVertices:region.restVertices,triangles:region.triangles,
            eyeCenters:region.eyeCenters.isEmpty ? eyeCenters : region.eyeCenters)
    }
}

// -Nimah: Bounded background fitting during the initial scan, retaining the first valid observation.
@MainActor final class LaunchFitPreparation:ObservableObject {
    private var pending:Task<Void,Never>?
    private let cache:LaunchMakeupFit
    private let provider:any FaceLandmarkProviding
    private var candidate=LaunchMakeupFit()
    private var generation=UUID()
    private var attempts=0
    init(cache:LaunchMakeupFit = .shared,provider:any FaceLandmarkProviding = VisionFaceLandmarkProvider(requireEyeFormula:false)) {
        self.cache=cache;self.provider=provider
    }
    func submit(_ input:FaceLandmarkFrame) {
        guard pending==nil,!candidate.hasFit else { return }
        let token=generation
        attempts += 1
        pending=Task {
            _=await Task.detached(priority:.userInitiated) { [candidate,provider] in candidate.prepare(input,provider:provider) }.value
            guard generation==token else { return }
            // -Nimah: Local stage/counter only; never log images, landmarks or mesh coordinates.
            UserDefaults.standard.set("attempts=\(attempts);stage=\(candidate.diagnostic)",forKey:"makeupFitDiagnostic.v1")
            pending=nil
        }
    }
    func finish() async -> Bool { await pending?.value;return cache.replace(with:candidate) }
    func restart() { generation=UUID();attempts=0;pending?.cancel();pending=nil;candidate=LaunchMakeupFit();UserDefaults.standard.set("attempts=0;stage=waiting_for_frame",forKey:"makeupFitDiagnostic.v1") }
}
