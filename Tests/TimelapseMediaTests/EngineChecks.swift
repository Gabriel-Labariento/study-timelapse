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
    engine.setPreviewVisible(false)
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

private final class EngineObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0, images = 0, frames = 0
    func poll() { lock.lock(); polls += 1; lock.unlock() }
    func image() { lock.lock(); images += 1; lock.unlock() }
    func frame() { lock.lock(); frames += 1; lock.unlock() }
    func snapshot() -> (polls: Int, images: Int, frames: Int) {
        lock.lock(); defer { lock.unlock() }; return (polls, images, frames)
    }
}
private final class CountingFrames: CaptureFrameProvider {
    let screen: CVPixelBuffer, camera: CVPixelBuffer, observations: EngineObservations
    init(_ screen: CVPixelBuffer, _ camera: CVPixelBuffer, _ observations: EngineObservations) {
        self.screen = screen; self.camera = camera; self.observations = observations
    }
    func latestPair(now: Double) -> (CVPixelBuffer, CVPixelBuffer)? { observations.poll(); return (screen, camera) }
}
private final class CountingWriter: MovieWriting {
    let observations: EngineObservations
    var frameCount: Int64 = 0
    var isReady: Bool { true }
    var failure: Error? { nil }
    init(_ observations: EngineObservations) { self.observations = observations }
    func makeBuffer() throws -> CVPixelBuffer { try Compositor.makeBuffer() }
    func append(frame: CVPixelBuffer, index: Int64) throws {
        precondition(index == frameCount); frameCount += 1; observations.frame()
    }
    func finish(completion: @escaping (Result<URL, Error>) -> Void) { completion(.failure(RecordingError("Synthetic writer"))) }
    func cancel() {}
}
func checkHiddenPreviewKeepsRecording(screen: CVPixelBuffer, camera: CVPixelBuffer, destination: URL) async throws {
    let observations = EngineObservations()
    let errors = FaultBox()
    let engine = RecordingEngine(sources: CountingFrames(screen, camera, observations), settings: RecordingSettings(speed: 10),
        writerFactory: { _, _ in CountingWriter(observations) },
        onSnapshot: { if $0.image != nil { observations.image() } }, onError: { errors.set($0) })
    engine.setPreviewVisible(false)
    engine.startPreview()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        engine.startRecording(destination: destination, replaceExisting: false) { continuation.resume(with: $0) }
    }
    let start = ProcessInfo.processInfo.systemUptime
    try await Task.sleep(nanoseconds: 1_200_000_000)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in engine.pause { continuation.resume() } }
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let hidden = observations.snapshot()
    precondition(errors.value == nil)
    precondition(hidden.images == 0, "Hidden window still rendered previews")
    precondition(hidden.frames >= 3, "Hiding the window stopped or slowed recording")
    precondition(hidden.polls <= Int(ceil(elapsed * 20)) + 5, "Hidden recording still polls excessively: \(hidden.polls)")
    engine.setPreviewVisible(true)
    let deadline = Date().addingTimeInterval(1)
    while observations.snapshot().images == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    let restored = observations.snapshot()
    precondition(restored.images > 0, "Preview did not resume when shown")
    precondition(restored.frames == hidden.frames, "Paused recording appended frames")
    engine.shutdown()
    print("PASS: hidden preview rendered 0 images, recorded \(hidden.frames) frames, \(hidden.polls) source reads in \(String(format: "%.2f", elapsed)) s; preview restored without resuming recording")
}
