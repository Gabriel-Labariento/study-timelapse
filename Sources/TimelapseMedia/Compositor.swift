import CoreImage
import CoreVideo
import TimelapseCore

public struct RecordingError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class Compositor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public init() {}
    public func render(screen: CVPixelBuffer, camera: CVPixelBuffer, settings: RecordingSettings, into buffer: CVPixelBuffer) throws {
        guard CVPixelBufferGetWidth(buffer) == 1920, CVPixelBufferGetHeight(buffer) == 1080 else {
            throw RecordingError("The output frame must be 1920 × 1080.")
        }
        let canvas = CGRect(origin: .zero, size: CompositionLayout.canvas)
        let screenImage = CIImage(cvPixelBuffer: screen)
        let screenRect = CompositionLayout.screenRect(source: screenImage.extent.size, canvas: canvas.size)
        let fitted = transform(screenImage, to: screenRect, fill: false)
        let inset = CompositionLayout.cameraRect(canvas: canvas.size, fraction: settings.insetFraction, corner: settings.corner)
        // Mirror the front-camera view, as in a familiar webcam preview.
        let originalCamera = CIImage(cvPixelBuffer: camera)
        let mirrored = originalCamera.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: originalCamera.extent.width, ty: 0))
        let cropped = transform(mirrored, to: inset, fill: true)
        let base = CIImage(color: .black).cropped(to: canvas)
        let border = CIImage(color: CIColor(red: 0.92, green: 0.94, blue: 0.90)).cropped(to: inset.insetBy(dx: -3, dy: -3))
        let composed = cropped.composited(over: border.composited(over: fitted.composited(over: base)))
        context.render(composed, to: buffer, bounds: canvas, colorSpace: colorSpace)
    }
    private func transform(_ image: CIImage, to rect: CGRect, fill: Bool) -> CIImage {
        let sx = rect.width / image.extent.width, sy = rect.height / image.extent.height
        let scale = fill ? max(sx, sy) : min(sx, sy)
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let scaled = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let moved = scaled.transformed(by: CGAffineTransform(translationX: rect.midX-scaled.extent.midX, y: rect.midY-scaled.extent.midY))
        return moved.cropped(to: rect)
    }
    public func preview(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        return context.createCGImage(image, from: image.extent)
    }
    public static func makeBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        guard result == kCVReturnSuccess, let buffer else { throw RecordingError("Unable to allocate a video frame.") }
        return buffer
    }
}
