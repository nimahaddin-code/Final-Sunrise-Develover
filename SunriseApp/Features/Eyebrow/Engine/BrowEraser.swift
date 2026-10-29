// Hides the natural brow for the MediaPipe brow path. Each brow is unwrapped into its own brow-space texture; the skin
// is estimated without the landmark area, the real brow edge is found as the pixels clearly darker than that estimate,
// and the whole brow is filled from the skin around it (push-pull over the mip pyramid), optionally replaced by
// MI-GAN's inpainting (`BrowInpainter`), given full-resolution forehead texture and smoothed over time. The brow strip
// lays the result back on the face where the hide mask says.
// All GPU work is encoded into the engine's command buffer on its render queue; the model runs on its own queue.
@preconcurrency import Metal
import QuartzCore
import simd

/// One vertex of the unwrap grid. brow: u, w (brow widths), observed half thickness, side (0 right, 1 left).
/// raw: camera coordinates (xy) and the face-crop clip position for the model's mask (zw). conceal: lower core and end.
struct BrowUnwrapVertex {
    var brow: SIMD4<Float>
    var raw: SIMD4<Float>
    var conceal: SIMD4<Float>
}

final class BrowEraser: @unchecked Sendable {
    /// Brow-space extent of the unwrap: u as the brow strip, w from below the brow up into the forehead (the fill's
    /// texture is taken from a band 0.45...0.63 above the centerline).
    static let space = SIMD4<Float>(BeautyBlushEngine.browExtent.x, BeautyBlushEngine.browExtent.y, -0.5, 0.75)
    static let columns = 48, rows = 20
    static var vertexCount: Int { (columns + 1) * (rows + 1) }
    static let width = 256, height = 128
    /// The model is asked again at most this often; its result stays attached to the brow in between.
    static let modelInterval: Double = 0.12
    /// While the face holds still the model is asked again only this often: its answer is mapped into brow space, so it
    /// stays on the brow as the head moves, and is blended out 1.5 s after it was asked.
    static let modelRefresh: Double = 1.0
    /// How far the face crop must move, scale or turn (as a fraction of its size) for the model to be asked again sooner.
    static let modelMoveFraction: Float = 0.06

    private struct ModelResult { let rgba: [UInt8]; let vertices: [BrowUnwrapVertex] }
    private let device: MTLDevice
    private let unwrapPipeline, hairPipeline, fillPipeline, cropPipeline, cropMaskPipeline, modelPipeline: MTLRenderPipelineState
    /// Known skin from the landmarks alone (premultiplied, mipmapped), the unmasked camera (mipmapped), the skin
    /// estimate from the first, known skin once the detected brow edge is removed too (mipmapped), and the hide mask.
    private let unwrap, raw, estimate, known, hideMask: MTLTexture
    private var fills: [MTLTexture]
    private let modelBrow: MTLTexture
    private let cropColor, cropMask: MTLTexture
    private var modelCrops: [MTLTexture]
    private let indices: MTLBuffer
    private var vertexBuffers: [MTLBuffer]
    private var slot = 0, fillIndex = 0, modelCropIndex = 0
    private var lastTime: Double?
    let inpainter: BrowInpainter
    private let modelQueue = DispatchQueue(label: "sunrise.brow-inpaint", qos: .userInitiated)
    private let lock = NSLock()
    private var modelInFlight = false, pending: ModelResult?
    private var lastRequest: Double = -.infinity, modelTime: Double?, modelWeight: Float = 0
    private var lastRequestCrop: simd_float4x4?
    private(set) var lastModelError: String?

    /// The current fill, one slice per brow (0 right, 1 left), linear RGB in brow space.
    var fill: MTLTexture { fills[fillIndex] }
    /// This frame's hidden area (landmarks plus the detected brow edge), 0...1 per brow slice, mipmapped.
    var hide: MTLTexture { hideMask }

    init(device: MTLDevice, library: MTLLibrary, inpainter: BrowInpainter = BrowInpainter()) throws {
        self.device = device
        self.inpainter = inpainter
        func pipeline(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat, _ second: MTLPixelFormat? = nil) throws -> MTLRenderPipelineState {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = library.makeFunction(name: vertex); p.fragmentFunction = library.makeFunction(name: fragment)
            p.colorAttachments[0].pixelFormat = format
            if let second { p.colorAttachments[1].pixelFormat = second }
            return try device.makeRenderPipelineState(descriptor: p)
        }
        unwrapPipeline = try pipeline("browUnwrapVertex", "browUnwrapFragment", .rgba16Float, .rgba16Float)
        hairPipeline = try pipeline("browUnwrapVertex", "browHairFragment", .rgba16Float, .r16Float)
        fillPipeline = try pipeline("browTextureVertex", "browFillFragment", .rgba16Float)
        cropPipeline = try pipeline("browTextureVertex", "browCropFragment", .rgba8Unorm)
        cropMaskPipeline = try pipeline("browCropMaskVertex", "browCropMaskFragment", .r8Unorm)
        modelPipeline = try pipeline("browUnwrapVertex", "browModelFragment", .rgba16Float)
        func array(mipmapped: Bool, _ format: MTLPixelFormat = .rgba16Float) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: Self.width, height: Self.height, mipmapped: mipmapped)
            d.textureType = .type2DArray; d.arrayLength = 2; d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            guard let t = device.makeTexture(descriptor: d) else { throw CocoaError(.featureUnsupported) }
            return t
        }
        func shared(_ format: MTLPixelFormat) throws -> MTLTexture {
            let side = BrowInpainter.side
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: side, height: side, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .shared
            guard let t = device.makeTexture(descriptor: d) else { throw CocoaError(.featureUnsupported) }
            return t
        }
        unwrap = try array(mipmapped: true); raw = try array(mipmapped: true); estimate = try array(mipmapped: false)
        known = try array(mipmapped: true); hideMask = try array(mipmapped: true, .r16Float)
        fills = [try array(mipmapped: false), try array(mipmapped: false)]
        modelBrow = try array(mipmapped: false)
        cropColor = try shared(.rgba8Unorm); cropMask = try shared(.r8Unorm)
        modelCrops = [try shared(.rgba8Unorm), try shared(.rgba8Unorm)]
        var grid: [UInt16] = []
        for side in 0..<2 {
            for row in 0..<Self.rows {
                for column in 0..<Self.columns {
                    let a = side * Self.vertexCount + row * (Self.columns + 1) + column, b = a + 1, c = a + Self.columns + 1, d = c + 1
                    grid += [a, b, c, b, d, c].map { UInt16($0) }
                }
            }
        }
        guard let buffer = grid.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else {
            throw CocoaError(.featureUnsupported)
        }
        indices = buffer
        vertexBuffers = (0..<3).compactMap { _ in device.makeBuffer(length: Self.vertexCount * 2 * MemoryLayout<BrowUnwrapVertex>.stride, options: .storageModeShared) }
        guard vertexBuffers.count == 3 else { throw CocoaError(.featureUnsupported) }
    }

    /// Forget the previous frame (temporal blend) and any model result, e.g. after the face was lost.
    func reset() {
        lastTime = nil
        lock.lock(); pending = nil; modelTime = nil; modelWeight = 0; lastRequestCrop = nil; lock.unlock()
    }

    private var indicesPerSide: Int { Self.columns * Self.rows * 6 }

    /// Encodes this frame's fill into `command`. `uniforms` are the engine's shader uniforms (camera decoding);
    /// `cropToRaw` maps the model's face crop to camera coordinates, nil when there is no face crop.
    /// `modelInterval` is the shortest time between model requests (nil: the model is off, for a hot phone).
    func encode(vertices: [BrowUnwrapVertex], cropToRaw: simd_float4x4?, uniforms: [UInt8], y: MTLTexture, cb: MTLTexture,
                timestamp: Double, modelInterval: Double? = BrowEraser.modelInterval, command: MTLCommandBuffer) {
        guard vertices.count == Self.vertexCount * 2 else { return }
        let buffer = vertexBuffers[slot % 3]; slot += 1
        vertices.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
        var space = Self.space
        // 1. Unwrap each brow: known skin from the landmarks alone, and the unmasked camera.
        drawGrid(buffer: buffer, command: command, pipeline: unwrapPipeline, targets: [unwrap, raw]) { e in
            uniforms.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            e.setFragmentTexture(y, index: 0); e.setFragmentTexture(cb, index: 1)
        }
        guard let push = command.makeBlitCommandEncoder() else { return }
        push.generateMipmaps(for: unwrap); push.generateMipmaps(for: raw); push.endEncoding()
        // 2. Skin estimate without the landmark area, to find the real brow edge against.
        encodeFill(source: unwrap, target: estimate, previous: estimate, blend: 1, modelWeight: 0, detail: 0, finest: 4, command: command)
        // 3. The detected brow edge joins the hidden area; known skin without it, and the hide mask.
        drawGrid(buffer: buffer, command: command, pipeline: hairPipeline, targets: [known, hideMask]) { e in
            e.setFragmentBytes(&space, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            e.setFragmentTexture(self.raw, index: 0); e.setFragmentTexture(self.estimate, index: 1)
        }
        guard let pyramid = command.makeBlitCommandEncoder() else { return }
        pyramid.generateMipmaps(for: known); pyramid.generateMipmaps(for: hideMask); pyramid.endEncoding()
        // 4. A finished model result goes into brow space with the geometry of the frame it was asked about.
        lock.lock(); let result = pending; pending = nil; lock.unlock()
        if let result, result.vertices.count == Self.vertexCount * 2 { encodeModelResult(result, timestamp: timestamp, command: command) }
        lock.lock()
        let fresh = modelTime.map { timestamp - $0 < 1.5 } ?? false
        let dt = lastTime.map { timestamp - $0 } ?? .infinity
        let step = dt > 0 && dt < 0.3 ? Float(1 - exp(-dt / 0.2)) : 1
        modelWeight += ((fresh ? 1 : 0) - modelWeight) * step
        let weight = modelWeight
        lock.unlock()
        // 5. The fill: push-pull, the model where it has answered, forehead texture, blended with the previous frame.
        let blend = dt > 0 && dt < 0.3 ? Float(1 - exp(-dt / 0.12)) : 1
        encodeFill(source: known, target: fills[1 - fillIndex], previous: fills[fillIndex], blend: blend, modelWeight: weight, detail: 1, command: command)
        fillIndex = 1 - fillIndex; lastTime = timestamp
        // 6. Ask the model again once the last request is answered.
        if let cropToRaw, let modelInterval, inpainter.isAvailable {
            requestModel(vertices: vertices, buffer: buffer, cropToRaw: cropToRaw, uniforms: uniforms, y: y, cb: cb, timestamp: timestamp,
                         minimumInterval: modelInterval, command: command)
        }
    }

    /// Draws the unwrap grid into slice 0 (right brow) and slice 1 (left brow) of each target.
    private func drawGrid(buffer: MTLBuffer, command: MTLCommandBuffer, pipeline: MTLRenderPipelineState, targets: [MTLTexture],
                          bind: (MTLRenderCommandEncoder) -> Void) {
        var space = Self.space
        for side in 0..<2 {
            let pass = MTLRenderPassDescriptor()
            for (i, target) in targets.enumerated() {
                pass.colorAttachments[i].texture = target; pass.colorAttachments[i].slice = side
                pass.colorAttachments[i].loadAction = .clear; pass.colorAttachments[i].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                pass.colorAttachments[i].storeAction = .store
            }
            guard let e = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            e.setRenderPipelineState(pipeline); e.setCullMode(.none)
            e.setVertexBuffer(buffer, offset: 0, index: 0); e.setVertexBytes(&space, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            bind(e)
            e.drawIndexedPrimitives(type: .triangle, indexCount: indicesPerSide, indexType: .uint16, indexBuffer: indices,
                                    indexBufferOffset: side * indicesPerSide * MemoryLayout<UInt16>.stride)
            e.endEncoding()
        }
    }

    /// Push-pull fill of `source` (premultiplied known skin, mipmapped) into both slices of `target`.
    private func encodeFill(source: MTLTexture, target: MTLTexture, previous: MTLTexture, blend: Float, modelWeight: Float, detail: Float,
                            finest: Int = 0, command: MTLCommandBuffer) {
        var params = (SIMD4<Float>(0, blend, modelWeight, Float(source.mipmapLevelCount)), Self.space, SIMD4<Float>(detail, Float(finest), 0, 0))
        for side in 0..<2 {
            params.0.x = Float(side)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target; pass.colorAttachments[0].slice = side
            pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
            guard let e = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            e.setRenderPipelineState(fillPipeline)
            e.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * 3, index: 0)
            e.setFragmentTexture(source, index: 0); e.setFragmentTexture(previous, index: 1)
            e.setFragmentTexture(modelBrow, index: 2); e.setFragmentTexture(raw, index: 3)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        }
    }

    private func encodeModelResult(_ result: ModelResult, timestamp: Double, command: MTLCommandBuffer) {
        let crop = modelCrops[modelCropIndex]; modelCropIndex = 1 - modelCropIndex
        let side = BrowInpainter.side
        result.rgba.withUnsafeBytes { crop.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: side * 4) }
        guard let buffer = result.vertices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return }
        var space = Self.space
        for slice in 0..<2 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = modelBrow; pass.colorAttachments[0].slice = slice
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            guard let e = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            e.setRenderPipelineState(modelPipeline); e.setCullMode(.none)
            e.setVertexBuffer(buffer, offset: 0, index: 0); e.setVertexBytes(&space, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            e.setFragmentTexture(crop, index: 0)
            e.drawIndexedPrimitives(type: .triangle, indexCount: indicesPerSide, indexType: .uint16, indexBuffer: indices,
                                    indexBufferOffset: slice * indicesPerSide * MemoryLayout<UInt16>.stride)
            e.endEncoding()
        }
        lock.lock(); modelTime = timestamp; lock.unlock()
    }

    /// Whether the model should be asked again: never sooner than `minimumInterval`, then once the face crop has moved
    /// noticeably since the last request, or `modelRefresh` has passed.
    static func modelDue(timestamp: Double, lastRequest: Double, crop: simd_float4x4, lastCrop: simd_float4x4?, minimumInterval: Double) -> Bool {
        let elapsed = timestamp - lastRequest
        guard elapsed >= minimumInterval else { return false }
        guard let lastCrop, elapsed < max(modelRefresh, minimumInterval) else { return true }
        // The crop's corners, before and after, measured against the crop's size.
        let corners = [SIMD4<Float>(0, 0, 0, 1), SIMD4(1, 0, 0, 1), SIMD4(0, 1, 0, 1), SIMD4(1, 1, 0, 1)]
        let before = corners.map { lastCrop * $0 }, after = corners.map { crop * $0 }
        let size = max(simd_distance(SIMD2(before[0].x, before[0].y), SIMD2(before[3].x, before[3].y)), 1e-6)
        let moved = zip(before, after).map { simd_distance(SIMD2($0.x, $0.y), SIMD2($1.x, $1.y)) }.max() ?? 0
        return moved / size > modelMoveFraction
    }

    private func requestModel(vertices: [BrowUnwrapVertex], buffer: MTLBuffer, cropToRaw: simd_float4x4, uniforms: [UInt8],
                              y: MTLTexture, cb: MTLTexture, timestamp: Double, minimumInterval: Double, command: MTLCommandBuffer) {
        lock.lock()
        guard !modelInFlight,
              Self.modelDue(timestamp: timestamp, lastRequest: lastRequest, crop: cropToRaw, lastCrop: lastRequestCrop, minimumInterval: minimumInterval)
        else { lock.unlock(); return }
        modelInFlight = true; lastRequest = timestamp; lastRequestCrop = cropToRaw
        lock.unlock()
        var matrix = cropToRaw
        let color = MTLRenderPassDescriptor()
        color.colorAttachments[0].texture = cropColor; color.colorAttachments[0].loadAction = .dontCare; color.colorAttachments[0].storeAction = .store
        let mask = MTLRenderPassDescriptor()
        mask.colorAttachments[0].texture = cropMask; mask.colorAttachments[0].loadAction = .clear; mask.colorAttachments[0].storeAction = .store
        guard let e = command.makeRenderCommandEncoder(descriptor: color) else { lock.lock(); modelInFlight = false; lock.unlock(); return }
        e.setRenderPipelineState(cropPipeline)
        uniforms.withUnsafeBytes { e.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        e.setFragmentBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        e.setFragmentTexture(y, index: 0); e.setFragmentTexture(cb, index: 1)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); e.endEncoding()
        guard let m = command.makeRenderCommandEncoder(descriptor: mask) else { lock.lock(); modelInFlight = false; lock.unlock(); return }
        var space = Self.space
        m.setRenderPipelineState(cropMaskPipeline); m.setCullMode(.none); m.setVertexBuffer(buffer, offset: 0, index: 0)
        m.setFragmentBytes(&space, length: MemoryLayout<SIMD4<Float>>.stride, index: 0); m.setFragmentTexture(hideMask, index: 0)
        m.drawIndexedPrimitives(type: .triangle, indexCount: indicesPerSide * 2, indexType: .uint16, indexBuffer: indices, indexBufferOffset: 0)
        m.endEncoding()
        let side = BrowInpainter.side, colorTexture = cropColor, maskTexture = cropMask
        command.addCompletedHandler { [weak self] _ in
            var rgba = [UInt8](repeating: 0, count: side * side * 4), hole = [UInt8](repeating: 0, count: side * side)
            rgba.withUnsafeMutableBytes { colorTexture.getBytes($0.baseAddress!, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0) }
            hole.withUnsafeMutableBytes { maskTexture.getBytes($0.baseAddress!, bytesPerRow: side, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0) }
            self?.modelQueue.async { [weak self] in
                guard let self else { return }
                let output: [UInt8]?
                var failure: String?
                do { output = try self.inpainter.inpaint(rgba: rgba, hole: hole) } catch { output = nil; failure = "\(error)" }
                self.lock.lock()
                self.lastModelError = failure
                if let output { self.pending = ModelResult(rgba: output, vertices: vertices) }
                self.modelInFlight = false
                self.lock.unlock()
            }
        }
    }

    // MARK: Geometry

    /// An upright, FFHQ-like square face crop for the model: eyes on a horizontal line about 40% from the top,
    /// width twice the outer-eye span, both brows inside. Maps crop coordinates (0...1, y down) to camera coordinates.
    static func faceCrop(_ o: BrowObservation) -> simd_float4x4? {
        guard let r = o.eyes[.subjectRight], let l = o.eyes[.subjectLeft] else { return nil }
        let brows = o.brows.values.flatMap { $0.upper + $0.lower }
        guard !brows.isEmpty else { return nil }
        let span = simd_distance(r.outer, l.outer)
        guard span > 1 else { return nil }
        let axis = (l.outer - r.outer) / span, eyes = (r.outer + l.outer) / 2
        let lift = brows.reduce(SIMD2<Float>.zero, +) / Float(brows.count) - eyes
        var up = lift - simd_dot(lift, axis) * axis
        guard simd_length(up) > 1e-3 else { return nil }
        up = simd_normalize(up)
        let side = span * 2, down = -up
        let origin = eyes + down * (side * 0.1) - axis * (side * 0.5) - down * (side * 0.5)
        let image = SIMD2(Float(o.imageSize.width), Float(o.imageSize.height))
        let x = axis * side / image, y = down * side / image, t = origin / image
        return simd_float4x4(columns: (SIMD4(x.x, x.y, 0, 0), SIMD4(y.x, y.y, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(t.x, t.y, 0, 1)))
    }

    /// Crop coordinates (0...1, y down) of a camera pixel for `cropToRaw`.
    static func cropPoint(_ pixel: SIMD2<Float>, imageSize: CGSize, cropToRaw m: simd_float4x4) -> SIMD2<Float> {
        let image = SIMD2(Float(imageSize.width), Float(imageSize.height))
        let p = pixel / image, x = SIMD2(m.columns.0.x, m.columns.0.y), y = SIMD2(m.columns.1.x, m.columns.1.y)
        let d = p - SIMD2(m.columns.3.x, m.columns.3.y), det = x.x * y.y - x.y * y.x
        guard abs(det) > 1e-12 else { return SIMD2(-1, -1) }
        return SIMD2((d.x * y.y - d.y * y.x) / det, (x.x * d.y - x.y * d.x) / det)
    }

    #if DEBUG
    /// Push-pull on a synthetic unwrap: `known` (slice 0, width x height premultiplied RGBA floats) in, slice 0 out.
    func fillFixture(known: [Float], device: MTLDevice, commands: MTLCommandQueue) throws -> [Float] {
        let n = Self.width * Self.height
        guard known.count == n * 4, let command = commands.makeCommandBuffer() else { throw CocoaError(.coderInvalidValue) }
        let half = known.map { Float16($0).bitPattern }
        let staging = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: Self.width, height: Self.height, mipmapped: false)
        staging.storageMode = .shared; staging.usage = .shaderRead
        guard let source = device.makeTexture(descriptor: staging), let readback = device.makeTexture(descriptor: staging) else { throw CocoaError(.featureUnsupported) }
        half.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: Self.width * 8) }
        guard let copy = command.makeBlitCommandEncoder() else { throw CocoaError(.featureUnsupported) }
        for slice in 0..<2 {
            copy.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1),
                      to: unwrap, destinationSlice: slice, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        }
        copy.generateMipmaps(for: unwrap)
        for slice in 0..<2 {
            copy.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1),
                      to: raw, destinationSlice: slice, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        }
        copy.generateMipmaps(for: raw); copy.endEncoding()
        encodeFill(source: unwrap, target: fills[0], previous: fills[1], blend: 1, modelWeight: 0, detail: 0, command: command)
        guard let back = command.makeBlitCommandEncoder() else { throw CocoaError(.featureUnsupported) }
        back.copy(from: fills[0], sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1),
                  to: readback, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        back.endEncoding()
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bits = [UInt16](repeating: 0, count: n * 4)
        bits.withUnsafeMutableBytes { readback.getBytes($0.baseAddress!, bytesPerRow: Self.width * 8, from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0) }
        return bits.map { Float(Float16(bitPattern: $0)) }
    }
    /// The hide mask at brow-space (u, w) of `slice`, after an `encode` has completed.
    func hideFixture(u: Float, w: Float, slice: Int, commands: MTLCommandQueue) throws -> Float {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: Self.width, height: Self.height, mipmapped: false)
        d.storageMode = .shared; d.usage = .shaderRead
        guard let readback = device.makeTexture(descriptor: d), let command = commands.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw CocoaError(.featureUnsupported)
        }
        blit.copy(from: hideMask, sourceSlice: slice, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: Self.width, height: Self.height, depth: 1),
                  to: readback, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        let x = Int((u - Self.space.x) / (Self.space.y - Self.space.x) * Float(Self.width))
        let y = Int((Self.space.w - w) / (Self.space.w - Self.space.z) * Float(Self.height))
        var bits: UInt16 = 0
        readback.getBytes(&bits, bytesPerRow: Self.width * 2, from: MTLRegionMake2D(min(max(x, 0), Self.width - 1), min(max(y, 0), Self.height - 1), 1, 1), mipmapLevel: 0)
        return Float(Float16(bitPattern: bits))
    }
    #endif
}
