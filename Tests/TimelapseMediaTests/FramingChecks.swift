import Foundation
import CoreImage
import TimelapseCore
import TimelapseMedia

func checkFullFrameAndPreview() throws {
    let context = CIContext()
    let screen = try MediaChecks.makeBuffer(width: 1920, height: 1080)
    let camera = try MediaChecks.makeBuffer(width: 1280, height: 720)
    context.render(CIImage(color: .black), to: screen)
    // Colored strips at both edges must survive full-frame composition, including mirroring.
    let center = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
    let left = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 720))
    let right = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 1160, y: 0, width: 120, height: 720))
    context.render(left.composited(over: right.composited(over: center)), to: camera)
    let compositor = Compositor()
    let output = try Compositor.makeBuffer()
    func color(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return pixel
    }
    for corner in InsetCorner.allCases {
        let settings = RecordingSettings(corner: corner, insetFraction: 0.20, cameraFraming: .fullFrame)
        try compositor.render(screen: screen, camera: camera, settings: settings, into: output)
        let rect = CompositionLayout.cameraRect(canvas: CompositionLayout.canvas, fraction: 0.20, corner: corner, cameraAspectRatio: 16/9)
        let y = Int(rect.midY)
        let leftPixel = color(CIImage(cvPixelBuffer: output), x: Int(rect.minX)+10, y: y)
        let rightPixel = color(CIImage(cvPixelBuffer: output), x: Int(rect.maxX)-10, y: y)
        precondition(leftPixel[1] > 240 && rightPixel[0] > 240, "Full frame lost camera edges")
        guard let preview = compositor.preview(screen: screen, camera: camera, settings: settings) else { fatalError("No preview") }
        precondition(preview.width == 960 && preview.height == 540, "Preview isn't rendered at display resolution")
        let previewLeft = color(CIImage(cgImage: preview), x: (Int(rect.minX)+10)/2, y: y/2)
        precondition(previewLeft[1] > 240, "Preview and export framing differ")
        try compositor.render(screen: screen, camera: camera, settings: RecordingSettings(corner: corner, insetFraction: 0.20, cameraFraming: .cropped), into: output)
        let cropped = CompositionLayout.cameraRect(canvas: CompositionLayout.canvas, fraction: 0.20, corner: corner)
        let croppedPixel = color(CIImage(cvPixelBuffer: output), x: Int(cropped.minX)+10, y: Int(cropped.midY))
        precondition(croppedPixel[2] > 240, "Legacy crop didn't crop the edge")
    }
    print("PASS: uncropped camera edges, legacy crop, direct 960×540 preview, matching export geometry")
}
