import Foundation
import CoreVideo
import TimelapseCore
import TimelapseMedia

private final class SyntheticFrames: CaptureFrameProvider {
    let screen: CVPixelBuffer, camera: CVPixelBuffer
    init(_ screen: CVPixelBuffer, _ camera: CVPixelBuffer) { self.screen = screen; self.camera = camera }
    func latestPair(now: Double) -> (CVPixelBuffer, CVPixelBuffer)? { (screen, camera) }
}
private final class FaultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ value: String) { lock.lock(); stored = value; lock.unlock() }
}
// An asynchronously failing disk/encoder is the external boundary; test the real engine's response.
private final class FailingWriter: MovieWriting {
    private let fault = FaultBox()
    var frameCount: Int64 = 0
    var isReady: Bool { failure == nil }
    var failure: Error? { fault.value.map { RecordingError($0) } }
    func triggerFailure() { fault.set("Injected disk failure while paused") }
    func makeBuffer() throws -> CVPixelBuffer { try Compositor.makeBuffer() }
    func append(frame: CVPixelBuffer, index: Int64) throws { frameCount += 1 }
    func finish(completion: @escaping (Result<URL, Error>) -> Void) { completion(.failure(RecordingError("Injected disk failure while paused"))) }
    func cancel() {}
}
func checkPausedEncoderFailure(screen: CVPixelBuffer, camera: CVPixelBuffer, destination: URL) async throws {
    let writer = FailingWriter()
    let reported = FaultBox()
    let engine = RecordingEngine(sources: SyntheticFrames(screen, camera), settings: RecordingSettings(),
        writerFactory: { _, _ in writer }, onSnapshot: { _ in }, onError: { reported.set($0) })
    engine.startPreview()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        engine.startRecording(destination: destination, replaceExisting: false) { continuation.resume(with: $0) }
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        engine.pause { continuation.resume() }
    }
    writer.triggerFailure()
    let deadline = Date().addingTimeInterval(1)
    while reported.value == nil && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    engine.shutdown()
    precondition(reported.value == "Injected disk failure while paused", "Encoder failure was hidden while paused")
}
