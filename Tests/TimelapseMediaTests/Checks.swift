import Foundation
import AVFoundation
import CoreImage
import TimelapseCore
import TimelapseMedia

@main struct MediaChecks {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StudyTimelapseChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = CIContext()
        let screen = try makeBuffer(width: 1080, height: 1920)
        let camera = try makeBuffer(width: 640, height: 480)
        context.render(CIImage(color: CIColor(red: 1, green: 0, blue: 0)), to: screen)
        context.render(CIImage(color: CIColor(red: 0, green: 0, blue: 1)), to: camera)
        let compositor = Compositor()
        for corner in InsetCorner.allCases {
            let output = try makeBuffer(width: 1920, height: 1080)
            try compositor.render(screen: screen, camera: camera, settings: RecordingSettings(corner: corner), into: output)
            // Read in Core Image's bottom-left coordinate system.
            var pixel = [UInt8](repeating: 0, count: 4)
            let x = corner == .topLeft || corner == .bottomLeft ? 200 : 1600
            let y = corner == .topLeft || corner == .topRight ? 900 : 150
            context.render(CIImage(cvPixelBuffer: output), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            precondition(pixel[2] > 240 && pixel[0] < 10, "Camera is not in selected corner")
            context.render(CIImage(cvPixelBuffer: output), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 960, y: 540, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            precondition(pixel[0] > 240 && pixel[2] < 10, "Screen center is not preserved")
        }
        let destination = folder.appendingPathComponent("movie.mp4")
        let writer = try MovieWriter(destination: destination, replaceExisting: false)
        for index in 0..<90 {
            let deadline = Date().addingTimeInterval(10)
            while !writer.isReady && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
            precondition(writer.isReady, "Encoder remained blocked")
            var available: CVPixelBuffer?
            while available == nil && Date() < deadline {
                do { available = try writer.makeBuffer() }
                catch FramePoolError.exhausted { try await Task.sleep(nanoseconds: 5_000_000) }
            }
            guard let buffer = available else { fatalError("Pool blocked at frame \(index)") }
            try compositor.render(screen: screen, camera: camera, settings: RecordingSettings(), into: buffer)
            try writer.append(frame: buffer, index: Int64(index))
        }
        let url = try await finish(writer)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        precondition(tracks.count == 1)
        let size = try await tracks[0].load(.naturalSize)
        precondition(size == CGSize(width: 1920, height: 1080))
        let duration = try await asset.load(.duration).seconds
        precondition(abs(duration - 3) < 0.04, "Incorrect duration: \(duration)")
        let audio = try await asset.loadTracks(withMediaType: .audio)
        precondition(audio.isEmpty)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); precondition(reader.startReading())
        var count = 0; var last = -Double.infinity
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            precondition(time > last, "Timestamps are not increasing")
            last = time; count += 1
        }
        precondition(reader.status == .completed && count == 90, "Decoded \(count) frames")
        do { try writer.append(frame: screen, index: 90); fatalError("Accepted frame after finishing") } catch {}
        let protected = folder.appendingPathComponent("protected.mp4")
        let sentinel = Data("existing-video".utf8)
        try sentinel.write(to: protected)
        do { _ = try MovieWriter(destination: protected, replaceExisting: false); fatalError("Overwrote file") } catch {}
        let preserved = try Data(contentsOf: protected)
        precondition(preserved == sentinel)
        let empty = try MovieWriter(destination: folder.appendingPathComponent("empty.mp4"), replaceExisting: false)
        do { _ = try await finish(empty); fatalError("Published empty video") } catch {}
        precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("empty.mp4").path))
        let appeared = folder.appendingPathComponent("appeared-before-start.mp4")
        // Simulate a new destination selected in a dialog, then created by another process before Start.
        precondition(!FileManager.default.fileExists(atPath: appeared.path))
        try sentinel.write(to: appeared)
        do { _ = try MovieWriter(destination: appeared, replaceExisting: false); fatalError("Inferred overwrite consent") } catch {}
        let untouched = try Data(contentsOf: appeared)
        precondition(untouched == sentinel)
        try await checkPausedEncoderFailure(screen: screen, camera: camera, destination: folder.appendingPathComponent("fake.mp4"))
        print("PASS: engine paused-failure delivery, appearance-before-start protection, four inset positions, portrait fit, 90-frame H.264 export, duration, dimensions, silent audio, timestamps, existing-file safety, empty recording, post-finish rejection")
    }
    static func finish(_ writer: MovieWriter) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in writer.finish { continuation.resume(with: $0) } }
    }
    static func makeBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer)
        precondition(status == kCVReturnSuccess)
        return buffer!
    }
}
