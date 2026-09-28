import AVFoundation
import CoreImage
import TimelapseCore

/// Explicit diagnostic mode: generates synthetic images only, with no screen or camera access.
public enum SyntheticExport {
    public static func run(to destination: URL) async throws {
        let writer = try MovieWriter(destination: destination, replaceExisting: false)
        let compositor = Compositor()
        let context = CIContext()
        let screen = try Compositor.makeBuffer(), camera = try Compositor.makeBuffer()
        for index in 0..<90 {
            autoreleasepool {
                let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
                let paper = CIImage(color: CIColor(red: 0.92, green: 0.95, blue: 0.99)).cropped(to: bounds)
                let stripe = CIImage(color: CIColor(red: 0.23, green: 0.36, blue: 0.65)).cropped(to: CGRect(x: index * 16, y: 200, width: 350, height: 680))
                context.render(stripe.composited(over: paper), to: screen)
                context.render(CIImage(color: CIColor(red: 0.25, green: 0.55, blue: 0.50)), to: camera)
            }
            let deadline = Date().addingTimeInterval(10)
            var available: CVPixelBuffer?
            while available == nil && Date() < deadline {
                if let failure = writer.failure { throw failure }
                if writer.isReady {
                    do { available = try writer.makeBuffer() }
                    catch FramePoolError.exhausted {}
                }
                if available == nil { try await Task.sleep(nanoseconds: 5_000_000) }
            }
            guard let buffer = available else { writer.cancel(); throw RecordingError("Synthetic export timed out.") }
            try compositor.render(screen: screen, camera: camera, settings: RecordingSettings(), into: buffer)
            try writer.append(frame: buffer, index: Int64(index))
        }
        let url: URL = try await withCheckedThrowingContinuation { continuation in
            writer.finish { continuation.resume(with: $0) }
        }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw RecordingError("Synthetic movie has no video track.") }
        let duration = try await asset.load(.duration)
        let size = try await track.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw RecordingError("Cannot decode synthetic export.") }
        var count = 0
        while output.copyNextSampleBuffer() != nil { count += 1 }
        guard reader.status == .completed, count == 90, size == CGSize(width: 1920, height: 1080), abs(duration.seconds-3) < 0.04 else {
            throw RecordingError("Synthetic verification failed: \(count) frames, \(size), \(duration.seconds) seconds.")
        }
        print("PASS: bundled app exported and decoded 90 frames, 1920×1080, 3 seconds: \(url.path)")
    }
}
