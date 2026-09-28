import Foundation

public struct SamplingClock {
    public let interval: Double
    public private(set) var frameCount: Int64 = 0
    private var segmentStart: Double?
    private var accumulated: Double = 0
    private var nextSample: Double = 0
    public init(speed: Int) {
        precondition([10, 30, 60].contains(speed))
        interval = Double(speed) / 30
    }
    public mutating func start(at now: Double) {
        accumulated = 0; frameCount = 0; segmentStart = now; nextSample = now
    }
    public mutating func pause(at now: Double) {
        if let start = segmentStart { accumulated += max(0, now - start) }
        segmentStart = nil
    }
    public mutating func resume(at now: Double) {
        guard segmentStart == nil else { return }
        segmentStart = now; nextSample = now + interval
    }
    public func activeElapsed(at now: Double) -> Double {
        accumulated + (segmentStart.map { max(0, now - $0) } ?? 0)
    }
    public func isDue(at now: Double) -> Bool { segmentStart != nil && now + 1e-8 >= nextSample }
    public mutating func takeSampleIfDue(at now: Double) -> Int64? {
        guard isDue(at: now) else { return nil }
        let index = frameCount
        frameCount += 1
        nextSample += max(1, floor((now - nextSample) / interval) + 1) * interval
        return index
    }
}

public enum FrameFreshness {
    public static func isUsable(screenAvailable: Bool, cameraTime: Double?, now: Double) -> Bool {
        guard screenAvailable, let time = cameraTime else { return false }
        // A producer may publish between the caller reading now and locking its frame snapshot.
        // Such a newer frame is fresh, never a source interruption.
        return max(0, now - time) <= 2
    }
}

public struct BackpressureMonitor {
    private var since: Double?
    public init() {}
    public mutating func shouldStop(ready: Bool, now: Double) -> Bool {
        if ready { since = nil; return false }
        if since == nil { since = now }
        return now - since! >= 2
    }
}
