import Foundation
import CoreGraphics

public enum InsetCorner: String, CaseIterable {
    case topLeft = "Top left", topRight = "Top right", bottomLeft = "Bottom left", bottomRight = "Bottom right"
}
public struct RecordingSettings {
    public var speed: Int
    public var corner: InsetCorner
    public var insetFraction: Double
    public init(speed: Int = 30, corner: InsetCorner = .bottomRight, insetFraction: Double = 0.28) {
        precondition([10, 30, 60].contains(speed))
        precondition([0.20, 0.28, 0.36].contains(insetFraction))
        self.speed = speed; self.corner = corner; self.insetFraction = insetFraction
    }
}
public enum CompositionLayout {
    public static let canvas = CGSize(width: 1920, height: 1080)
    public static func screenRect(source: CGSize, canvas: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = min(canvas.width / source.width, canvas.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (canvas.width-size.width)/2, y: (canvas.height-size.height)/2, width: size.width, height: size.height)
    }
    public static func cameraRect(canvas: CGSize, fraction: Double, corner: InsetCorner) -> CGRect {
        let width = canvas.width * fraction, height = width * 0.75
        let left = corner == .topLeft || corner == .bottomLeft
        let bottom = corner == .bottomLeft || corner == .bottomRight
        return CGRect(x: left ? 24 : canvas.width-width-24, y: bottom ? 24 : canvas.height-height-24, width: width, height: height)
    }
}
