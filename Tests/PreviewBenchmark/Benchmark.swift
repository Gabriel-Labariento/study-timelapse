import Foundation
import CoreImage
import Darwin
import TimelapseCore
import TimelapseMedia

@main struct PreviewBenchmark {
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    static func main() throws {
        let compositor = Compositor(), context = CIContext()
        let screen = try Compositor.makeBuffer(), camera = try Compositor.makeBuffer(), intermediate = try Compositor.makeBuffer()
        let gradient = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 1920, y: 1080)])!.outputImage!
        context.render(gradient, to: screen)
        context.render(CIFilter(name: "CICheckerboardGenerator")!.outputImage!, to: camera)
        let settings = RecordingSettings(cameraFraming: .cropped)
        let destination = CGContext(data: nil, width: 960, height: 540, bitsPerComponent: 8, bytesPerRow: 960*4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func measure(direct: Bool, count: Int) throws -> (wall: Double, cpu: Double) {
            let wall = ProcessInfo.processInfo.systemUptime, cpu = cpuSeconds()
            for _ in 0..<count {
                try autoreleasepool {
                    let image: CGImage?
                    if direct { image = compositor.preview(screen: screen, camera: camera, settings: settings) }
                    else {
                        try compositor.render(screen: screen, camera: camera, settings: settings, into: intermediate)
                        image = compositor.preview(from: intermediate)
                    }
                    guard let image else { throw RecordingError("No preview produced") }
                    destination.draw(image, in: CGRect(x: 0, y: 0, width: 960, height: 540))
                }
            }
            return (ProcessInfo.processInfo.systemUptime-wall, cpuSeconds()-cpu)
        }
        _ = try measure(direct: false, count: 15); _ = try measure(direct: true, count: 15)
        var old: [(wall: Double, cpu: Double)] = [], new: [(wall: Double, cpu: Double)] = []
        for round in 0..<3 {
            if round % 2 == 0 { old.append(try measure(direct: false, count: 150)); new.append(try measure(direct: true, count: 150)) }
            else { new.append(try measure(direct: true, count: 150)); old.append(try measure(direct: false, count: 150)) }
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count/2] }
        print("150 synthetic previews, median of 3 rounds; includes drawing each preview")
        print(String(format: "Full-HD intermediate: %.3f s wall, %.3f s process CPU", median(old.map(\.wall)), median(old.map(\.cpu))))
        print(String(format: "Direct preview:       %.3f s wall, %.3f s process CPU", median(new.map(\.wall)), median(new.map(\.cpu))))
        print("This measures preview processing, not camera power or battery life.")
    }
}
