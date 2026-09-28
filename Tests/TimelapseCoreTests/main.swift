import Foundation
import CoreGraphics
import TimelapseCore

final class CoreTests {
    func testSpeedsAndNoCatchupBurst() {
        for speed in [10, 30, 60] {
            var clock = SamplingClock(speed: speed)
            clock.start(at: 100)
            XCTAssertEqual(clock.takeSampleIfDue(at: 100), 0)
            let interval = Double(speed) / 30
            XCTAssertNil(clock.takeSampleIfDue(at: 100 + interval * 0.9))
            XCTAssertEqual(clock.takeSampleIfDue(at: 100 + interval), 1)
            XCTAssertEqual(clock.takeSampleIfDue(at: 1000), 2)
            XCTAssertNil(clock.takeSampleIfDue(at: 1000.01))
        }
    }
    func testPauseExcludesTimeAndResetsDeadline() {
        var clock = SamplingClock(speed: 30)
        clock.start(at: 100)
        XCTAssertEqual(clock.takeSampleIfDue(at: 100), 0)
        XCTAssertEqual(clock.takeSampleIfDue(at: 101), 1)
        clock.pause(at: 102)
        XCTAssertNil(clock.takeSampleIfDue(at: 500))
        XCTAssertEqual(clock.activeElapsed(at: 500), 2)
        clock.resume(at: 502)
        XCTAssertNil(clock.takeSampleIfDue(at: 502.5))
        XCTAssertEqual(clock.activeElapsed(at: 503), 3)
        XCTAssertEqual(clock.takeSampleIfDue(at: 503), 2)
    }
    func testUnreadyWriterDoesNotAdvanceClock() {
        var clock = SamplingClock(speed: 10)
        clock.start(at: 0)
        XCTAssertTrue(clock.isDue(at: 0))
        XCTAssertTrue(clock.isDue(at: 8))
        XCTAssertEqual(clock.takeSampleIfDue(at: 8), 0)
        XCTAssertEqual(clock.frameCount, 1)
    }
    func testPortraitScreenFitsWithoutCrop() {
        let rect = CompositionLayout.screenRect(source: CGSize(width: 1080, height: 1920), canvas: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(rect.width, 607.5)
        XCTAssertEqual(rect.height, 1080)
        XCTAssertEqual(rect.midX, 960)
        XCTAssertEqual(CompositionLayout.screenRect(source: .zero, canvas: CGSize(width: 1920, height: 1080)), .zero)
    }
    func testAllInsetCornersRemainInsideCanvas() {
        let canvas = CGSize(width: 1920, height: 1080)
        for corner in InsetCorner.allCases {
            for fraction in [0.20, 0.28, 0.36] {
                let r = CompositionLayout.cameraRect(canvas: canvas, fraction: fraction, corner: corner)
                XCTAssertEqual(r.width / r.height, 4 / 3.0, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(r.minX, 24)
                XCTAssertGreaterThanOrEqual(r.minY, 24)
                XCTAssertLessThanOrEqual(r.maxX, canvas.width - 24)
                XCTAssertLessThanOrEqual(r.maxY, canvas.height - 24)
                XCTAssertEqual(r.minX == 24, corner == .topLeft || corner == .bottomLeft)
                XCTAssertEqual(r.minY == 24, corner == .bottomLeft || corner == .bottomRight)
            }
        }
    }
    func testCameraFreshnessAndStaticScreen() {
        // Camera callback can publish just after the sampling clock was read.
        XCTAssertTrue(FrameFreshness.isUsable(screenAvailable: true, cameraTime: 10.001, now: 10))
        XCTAssertFalse(FrameFreshness.isUsable(screenAvailable: false, cameraTime: 10, now: 10))
        XCTAssertFalse(FrameFreshness.isUsable(screenAvailable: true, cameraTime: nil, now: 10))
        XCTAssertTrue(FrameFreshness.isUsable(screenAvailable: true, cameraTime: 99, now: 100))
        XCTAssertFalse(FrameFreshness.isUsable(screenAvailable: true, cameraTime: 97, now: 100))
    }
    func testStateRejectsDuplicateStartAndSamplesAfterFinishing() {
        var state = SessionState.idle
        XCTAssertTrue(state.transition(to: .preparing))
        XCTAssertFalse(state.transition(to: .preparing))
        XCTAssertFalse(state.acceptsSamples)
        XCTAssertTrue(state.transition(to: .recording))
        XCTAssertTrue(state.acceptsSamples)
        XCTAssertTrue(state.transition(to: .paused))
        XCTAssertFalse(state.acceptsSamples)
        XCTAssertTrue(state.transition(to: .recording))
        XCTAssertTrue(state.transition(to: .finishing))
        XCTAssertFalse(state.transition(to: .finishing))
        XCTAssertFalse(state.transition(to: .recording))
        XCTAssertFalse(state.acceptsSamples)
        XCTAssertTrue(state.transition(to: .idle))
    }
    func testInterruptionFromPreparingRecordingOrPaused() {
        for initial in [SessionState.preparing, .recording, .paused] {
            var state = initial
            XCTAssertTrue(state.transition(to: .finishing))
            XCTAssertFalse(state.transition(to: .finishing))
        }
    }
    func testDestinationNeverSilentlyReplacesNewFile() {
        XCTAssertFalse(DestinationPolicy.canPublish(existsNow: true, replacementApproved: false))
        XCTAssertTrue(DestinationPolicy.canPublish(existsNow: true, replacementApproved: true))
        XCTAssertTrue(DestinationPolicy.canPublish(existsNow: false, replacementApproved: false))
    }
    func testSaveRequiresExplicitReplacementConsent() {
        XCTAssertEqual(DestinationPolicy.saveDecision(existsNow: false, confirmation: nil), .start(replaceExisting: false))
        XCTAssertEqual(DestinationPolicy.saveDecision(existsNow: true, confirmation: nil), .confirmReplacement)
        XCTAssertEqual(DestinationPolicy.saveDecision(existsNow: true, confirmation: false), .cancel)
        XCTAssertEqual(DestinationPolicy.saveDecision(existsNow: true, confirmation: true), .start(replaceExisting: true))
    }
    func testDeadlineSchedulingAndPausedClock() {
        XCTAssertEqual(RecordingSchedule.delay(now: 10, sample: 10.033, preview: 10.1, status: 11), 0.033, accuracy: 0.0001)
        XCTAssertEqual(RecordingSchedule.delay(now: 10, sample: 11, preview: nil, status: 11), 0.25)
        XCTAssertEqual(RecordingSchedule.delay(now: 10, sample: nil, preview: 10.1, status: 11), 0.1, accuracy: 0.0001)
        XCTAssertEqual(RecordingSchedule.delay(now: 10, sample: 9, preview: nil, status: 11), 0.01)
        var clock = SamplingClock(speed: 30)
        clock.start(at: 10)
        XCTAssertEqual(clock.nextDeadline, 10)
        _ = clock.takeSampleIfDue(at: 10)
        XCTAssertEqual(clock.nextDeadline, 11)
        clock.pause(at: 10.5)
        XCTAssertNil(clock.nextDeadline)
        clock.resume(at: 20)
        XCTAssertEqual(clock.nextDeadline, 21)
    }
    func testFullFrameGeometryPreservesAspectRatio() {
        for corner in InsetCorner.allCases {
            let wide = CompositionLayout.cameraRect(canvas: CGSize(width: 1920, height: 1080), fraction: 0.28, corner: corner, cameraAspectRatio: 16/9)
            XCTAssertEqual(wide.width / wide.height, 16/9, accuracy: 0.0001)
            let portrait = CompositionLayout.cameraRect(canvas: CGSize(width: 1920, height: 1080), fraction: 0.36, corner: corner, cameraAspectRatio: 9/16)
            XCTAssertLessThanOrEqual(portrait.maxY, 1056)
            XCTAssertGreaterThanOrEqual(portrait.minY, 24)
            XCTAssertEqual(portrait.width / portrait.height, 9/16, accuracy: 0.0001)
        }
        XCTAssertEqual(RecordingSettings().cameraFraming, .fullFrame)
    }
    func testBackpressureTimeoutAndReset() {
        var pressure = BackpressureMonitor()
        XCTAssertFalse(pressure.shouldStop(ready: false, now: 10))
        XCTAssertFalse(pressure.shouldStop(ready: false, now: 11))
        XCTAssertTrue(pressure.shouldStop(ready: false, now: 12))
        XCTAssertFalse(pressure.shouldStop(ready: true, now: 13))
        XCTAssertFalse(pressure.shouldStop(ready: false, now: 14))
    }
}

let tests = CoreTests()
tests.testSpeedsAndNoCatchupBurst()
tests.testPauseExcludesTimeAndResetsDeadline()
tests.testUnreadyWriterDoesNotAdvanceClock()
tests.testPortraitScreenFitsWithoutCrop()
tests.testAllInsetCornersRemainInsideCanvas()
tests.testCameraFreshnessAndStaticScreen()
tests.testStateRejectsDuplicateStartAndSamplesAfterFinishing()
tests.testInterruptionFromPreparingRecordingOrPaused()
tests.testDestinationNeverSilentlyReplacesNewFile()
tests.testBackpressureTimeoutAndReset()
tests.testSaveRequiresExplicitReplacementConsent()
tests.testDeadlineSchedulingAndPausedClock()
tests.testFullFrameGeometryPreservesAspectRatio()
print("PASS: 13 core checks")
