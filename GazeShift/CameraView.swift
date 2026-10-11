import SwiftUI
import MetalKit
import CoreVideo
import simd

struct CameraView: UIViewRepresentable {
    let packet: RenderPacket?
    let onFailure: (String) -> Void
    func makeCoordinator() -> Renderer { Renderer(onFailure: onFailure) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.035, green: 0.065, blue: 0.09, alpha: 1)
        context.coordinator.configure(view)
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.packet = packet
        view.draw()
    }

    final class Renderer: NSObject, MTKViewDelegate {
        var packet: RenderPacket?
        private let onFailure: (String) -> Void
        private var commands: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var cache: CVMetalTextureCache?
        private let inFlight = DispatchSemaphore(value: 1)
        private var reportedFailure: String?
        private var drawCount = 0
        private var lastDiagnosticAt: TimeInterval = 0
        init(onFailure: @escaping (String) -> Void) { self.onFailure = onFailure }

        func configure(_ view: MTKView) {
            guard let device = view.device, let commands = device.makeCommandQueue() else { fail("Metal unavailable"); return }
            do {
                guard let url = Bundle.main.url(forResource: "CameraShaders", withExtension: "metal") else { fail("Camera shader resource missing"); return }
                // Host Metal Toolchain is optional; compile the bundled source once on-device.
                let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "cameraVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "cameraFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else { fail("Camera texture cache unavailable"); return }
                self.commands = commands
            } catch { fail("Camera shader: \(error.localizedDescription)") }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        func draw(in view: MTKView) {
            guard inFlight.wait(timeout: .now()) == .success else { view.setNeedsDisplay(); return }
            guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { inFlight.signal(); return }
            guard let buffer = commands?.makeCommandBuffer() else { inFlight.signal(); fail("Camera command buffer unavailable"); return }
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { inFlight.signal(); fail("Camera render encoder unavailable"); return }
            var retainedTextures: [CVMetalTexture] = []
            if let packet, let pipeline, let cache {
                drawCount += 1
                logDiagnostics(packet, drawableSize: view.drawableSize)
                guard packet.identity.isFresh(at: ProcessInfo.processInfo.systemUptime) else { encoder.endEncoding(); buffer.present(drawable); buffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }; buffer.commit(); return }
                var y: CVMetalTexture?
                var cbcr: CVMetalTexture?
                let image = packet.image
                let yResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, image, nil, .r8Unorm, CVPixelBufferGetWidthOfPlane(image, 0), CVPixelBufferGetHeightOfPlane(image, 0), 0, &y)
                let cbcrResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, image, nil, .rg8Unorm, CVPixelBufferGetWidthOfPlane(image, 1), CVPixelBufferGetHeightOfPlane(image, 1), 1, &cbcr)
                if yResult == kCVReturnSuccess, cbcrResult == kCVReturnSuccess, let y, let cbcr, let yTexture = CVMetalTextureGetTexture(y), let cbcrTexture = CVMetalTextureGetTexture(cbcr) {
                    retainedTextures = [y, cbcr]
                    let origin = packet.geometry.displayToRaw(.zero)
                    let x = packet.geometry.displayToRaw(CGPoint(x: 1, y: 0))
                    let yPoint = packet.geometry.displayToRaw(CGPoint(x: 0, y: 1))
                    var inverse = simd_float3x3(columns: (SIMD3(Float(x.x-origin.x), Float(x.y-origin.y), 0), SIMD3(Float(yPoint.x-origin.x), Float(yPoint.y-origin.y), 0), SIMD3(Float(origin.x), Float(origin.y), 1)))
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setFragmentTexture(yTexture, index: 0)
                    encoder.setFragmentTexture(cbcrTexture, index: 1)
                    encoder.setFragmentBytes(&inverse, length: MemoryLayout<simd_float3x3>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                } else { fail("Camera texture conversion failed") }
            }
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.addCompletedHandler { [inFlight, retainedTextures] completed in
                _ = retainedTextures
                inFlight.signal()
                if let error = completed.error { DispatchQueue.main.async { self.fail("Camera GPU: \(error.localizedDescription)") } }
            }
            buffer.commit()
        }

        private func logDiagnostics(_ packet: RenderPacket, drawableSize: CGSize) {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastDiagnosticAt >= 1 else { return }
            lastDiagnosticAt = now
            let image = packet.image
            var centerLuma = -1
            if CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess {
                if let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) {
                    let offset = CVPixelBufferGetHeightOfPlane(image, 0) / 2 * CVPixelBufferGetBytesPerRowOfPlane(image, 0) + CVPixelBufferGetWidthOfPlane(image, 0) / 2
                    centerLuma = Int(base.load(fromByteOffset: offset, as: UInt8.self))
                }
                CVPixelBufferUnlockBaseAddress(image, .readOnly)
            }
            let uv = packet.geometry.displayToRaw(CGPoint(x: 0.5, y: 0.5))
            NSLog("GazeShift renderer draw=%d image=%dx%d drawable=%.0fx%.0f centerY=%d centerUV=%.3f,%.3f ageMs=%.1f", drawCount, CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image), drawableSize.width, drawableSize.height, centerLuma, uv.x, uv.y, (now - (packet.identity.estimatedCaptureAt ?? packet.identity.receivedAt)) * 1000)
        }

        private func fail(_ message: String) {
            guard reportedFailure != message else { return }
            reportedFailure = message
            DispatchQueue.main.async { self.onFailure(message) }
        }
    }
}
