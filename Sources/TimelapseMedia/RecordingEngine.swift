import Foundation
import CoreGraphics
import CoreVideo
import TimelapseCore

public struct EngineSnapshot {
    public let elapsed: Double
    public let frames: Int64
    public let image: CGImage?
}

/// Mutable recording state belongs exclusively to queue. CaptureSources provides locked frame snapshots.
public final class RecordingEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "study.recording", qos: .userInitiated)
    private let delivery = DispatchSemaphore(value: 1)
    private let sources: CaptureFrameProvider
    private let writerFactory: (URL, Bool) throws -> MovieWriting
    private let compositor = Compositor()
    private var settings: RecordingSettings
    private var timer: DispatchSourceTimer?
    private var previewBuffer: CVPixelBuffer?
    private var writer: MovieWriting?
    private var clock: SamplingClock?
    private var pressure = BackpressureMonitor()
    private var lastPreview = 0.0
    private var startTime = 0.0
    private var hadPair = false
    private var failed = false
    private var finishing = false
    private let onSnapshot: (EngineSnapshot) -> Void
    private let onError: (String) -> Void
    public init(sources: CaptureFrameProvider, settings: RecordingSettings,
                writerFactory: @escaping (URL, Bool) throws -> MovieWriting = { try MovieWriter(destination: $0, replaceExisting: $1) },
                onSnapshot: @escaping (EngineSnapshot) -> Void, onError: @escaping (String) -> Void) {
        self.sources = sources; self.settings = settings; self.writerFactory = writerFactory
        self.onSnapshot = onSnapshot; self.onError = onError
    }
    public func startPreview() {
        queue.async { [self] in
            startTime = ProcessInfo.processInfo.systemUptime
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer; timer.resume()
        }
    }
    public func update(settings: RecordingSettings) {
        queue.async { [self] in if writer == nil { self.settings = settings } }
    }
    public func startRecording(destination: URL, replaceExisting: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            do {
                guard !failed, writer == nil, sources.latestPair(now: ProcessInfo.processInfo.systemUptime) != nil else {
                    throw RecordingError("Wait for a live screen and camera preview before recording.")
                }
                writer = try writerFactory(destination, replaceExisting)
                var clock = SamplingClock(speed: settings.speed)
                clock.start(at: ProcessInfo.processInfo.systemUptime)
                self.clock = clock
                DispatchQueue.main.async { completion(.success(())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    public func pause(completion: @escaping () -> Void = {}) {
        queue.async { [self] in
            clock?.pause(at: ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.async(execute: completion)
        }
    }
    public func resume() { queue.async { [self] in pressure = BackpressureMonitor(); clock?.resume(at: ProcessInfo.processInfo.systemUptime) } }
    public func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard !finishing else { return }
            finishing = true; timer?.cancel(); timer = nil
            clock?.pause(at: ProcessInfo.processInfo.systemUptime)
            guard let writer else {
                DispatchQueue.main.async { completion(.failure(RecordingError("No recording was started."))) }; return
            }
            writer.finish { result in DispatchQueue.main.async { completion(result) } }
        }
    }
    public func shutdown() {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            if !finishing { writer?.cancel() }
            writer = nil; clock = nil; previewBuffer = nil
        }
    }
    private func tick() {
        autoreleasepool {
            guard !failed, !finishing else { return }
            if let failure = writer?.failure { fail(failure.localizedDescription); return }
            let now = ProcessInfo.processInfo.systemUptime
            guard let (screen, camera) = sources.latestPair(now: now) else {
                if hadPair || now-startTime > 10 { fail("Live frames stopped arriving. Check the camera and screen permissions, then enable preview again.") }
                return
            }
            hadPair = true
            do {
                var movieBuffer: CVPixelBuffer?
                if let writer, clock?.isDue(at: now) == true {
                    if writer.isReady {
                        do { movieBuffer = try writer.makeBuffer() }
                        catch FramePoolError.exhausted { /* Bounded retry below, never accumulate frames. */ }
                    }
                    if pressure.shouldStop(ready: movieBuffer != nil, now: now) {
                        throw RecordingError("The video encoder was unable to keep up for two seconds. The completed portion will be saved if possible.")
                    }
                    if let movieBuffer {
                        try compositor.render(screen: screen, camera: camera, settings: settings, into: movieBuffer)
                        // Commit clock only after append succeeds.
                        try writer.append(frame: movieBuffer, index: clock!.frameCount)
                        _ = clock?.takeSampleIfDue(at: now)
                    }
                }
                guard now-lastPreview >= 0.1 else { return }
                lastPreview = now
                guard delivery.wait(timeout: .now()) == .success else { return }
                do {
                    let buffer: CVPixelBuffer
                    if let movieBuffer { buffer = movieBuffer }
                    else {
                        if previewBuffer == nil { previewBuffer = try Compositor.makeBuffer() }
                        buffer = previewBuffer!
                        try compositor.render(screen: screen, camera: camera, settings: settings, into: buffer)
                    }
                    let snapshot = EngineSnapshot(elapsed: clock?.activeElapsed(at: now) ?? 0,
                        frames: writer?.frameCount ?? 0, image: compositor.preview(from: buffer))
                    DispatchQueue.main.async { [self] in onSnapshot(snapshot); delivery.signal() }
                } catch { delivery.signal(); throw error }
            } catch { fail(error.localizedDescription) }
        }
    }
    private func fail(_ message: String) {
        guard !failed else { return }
        failed = true; timer?.cancel(); timer = nil
        DispatchQueue.main.async { [self] in onError(message) }
    }
}
