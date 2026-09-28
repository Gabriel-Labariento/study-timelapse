import AVFoundation
import TimelapseCore

/// All methods are called on the caller's serial recording queue. Completion runs on an unspecified queue.
public enum FramePoolError: Error { case exhausted }

public protocol MovieWriting: AnyObject {
    var frameCount: Int64 { get }
    var isReady: Bool { get }
    var failure: Error? { get }
    func makeBuffer() throws -> CVPixelBuffer
    func append(frame: CVPixelBuffer, index: Int64) throws
    func finish(completion: @escaping (Result<URL, Error>) -> Void)
    func cancel()
}

public final class MovieWriter: MovieWriting {
    public let destination: URL
    public let temporaryURL: URL
    public private(set) var frameCount: Int64 = 0
    private let replaceExisting: Bool
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var finishing = false
    public var isReady: Bool { !finishing && writer.status == .writing && input.isReadyForMoreMediaData }
    public var failure: Error? { writer.status == .failed ? writer.error : nil }

    public init(destination: URL, replaceExisting: Bool) throws {
        self.destination = destination; self.replaceExisting = replaceExisting
        guard DestinationPolicy.canPublish(existsNow: FileManager.default.fileExists(atPath: destination.path), replacementApproved: replaceExisting) else {
            throw RecordingError("A file already exists at the selected destination. Choose a new name.")
        }
        temporaryURL = destination.deletingLastPathComponent().appendingPathComponent(".study-\(UUID().uuidString).mp4")
        writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1920, AVVideoHeightKey: 1080,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoAllowFrameReorderingKey: false]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1920, kCVPixelBufferHeightKey as String: 1080,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw RecordingError("The H.264 encoder is unavailable.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecordingError("Unable to create the movie.") }
        writer.startSession(atSourceTime: .zero)
    }
    public func makeBuffer() throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw RecordingError("The video frame pool is unavailable.") }
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary, &buffer)
        if result == kCVReturnWouldExceedAllocationThreshold { throw FramePoolError.exhausted }
        guard result == kCVReturnSuccess, let buffer else { throw RecordingError("Unable to allocate an encoder frame.") }
        return buffer
    }
    public func append(frame: CVPixelBuffer, index: Int64) throws {
        guard isReady, index == frameCount else { throw RecordingError("The video encoder is not ready for this frame.") }
        guard CVPixelBufferGetWidth(frame) == 1920, CVPixelBufferGetHeight(frame) == 1080 else { throw RecordingError("Unexpected frame dimensions.") }
        guard adaptor.append(frame, withPresentationTime: CMTime(value: index, timescale: 30)) else {
            throw writer.error ?? RecordingError("Unable to write a video frame.")
        }
        frameCount += 1
    }
    public func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        guard !finishing else { completion(.failure(RecordingError("This recording is already finishing."))); return }
        finishing = true
        guard frameCount > 0, writer.status == .writing else {
            let error = writer.error ?? RecordingError("No video frames were recorded. Try a longer session.")
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temporaryURL)
            completion(.failure(error)); return
        }
        writer.endSession(atSourceTime: CMTime(value: frameCount, timescale: 30))
        input.markAsFinished()
        writer.finishWriting { [self] in
            guard writer.status == .completed else {
                completion(.failure(writer.error ?? RecordingError("The movie could not be finalized."))); return
            }
            do {
                let exists = FileManager.default.fileExists(atPath: destination.path)
                guard DestinationPolicy.canPublish(existsNow: exists, replacementApproved: replaceExisting) else {
                    throw RecordingError("A file appeared at the destination. Your completed movie is preserved at \(temporaryURL.path).")
                }
                if exists {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
                } else {
                    try FileManager.default.moveItem(at: temporaryURL, to: destination)
                }
                completion(.success(destination))
            } catch {
                completion(.failure(RecordingError("Could not publish the movie: \(error.localizedDescription)\nCompleted video: \(temporaryURL.path)")))
            }
        }
    }
    public func cancel() {
        guard !finishing else { return }
        finishing = true; writer.cancelWriting()
        try? FileManager.default.removeItem(at: temporaryURL)
    }
}
