import AppKit
import AVFoundation
import ScreenCaptureKit
import TimelapseCore

public struct DisplayChoice {
    public let id: CGDirectDisplayID
    public let name: String
}
public struct CameraChoice {
    public let id: String
    public let name: String
}

public protocol CaptureFrameProvider: AnyObject {
    func latestPair(now: Double) -> (CVPixelBuffer, CVPixelBuffer)?
}

/// One instance per preview/session. Source buffers are protected by lock; lifecycle calls are serialized by the controller.
public final class CaptureSources: NSObject, CaptureFrameProvider, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let screenQueue = DispatchQueue(label: "study.screen", qos: .userInitiated)
    private let cameraQueue = DispatchQueue(label: "study.camera", qos: .userInitiated)
    private var screenFrame: CVPixelBuffer?
    private var cameraFrame: CVPixelBuffer?
    private var cameraTime: Double?
    private var stream: SCStream?
    private var session: AVCaptureSession?
    private var observers: [NSObjectProtocol] = []
    private var stopped = false
    private var hasReportedError = false
    public var onError: ((String) -> Void)?

    public static func cameras() -> [CameraChoice] {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified)
        return discovery.devices.sorted { a, b in
            let aBuiltIn = a.deviceType == .builtInWideAngleCamera
            let bBuiltIn = b.deviceType == .builtInWideAngleCamera
            return aBuiltIn != bBuiltIn ? aBuiltIn : a.localizedName < b.localizedName
        }.map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
    }
    @MainActor public static func displays() -> [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return DisplayChoice(id: id, name: "\(screen.localizedName) · \(Int(screen.frame.width)) × \(Int(screen.frame.height))")
        }
    }
    public func start(displayID: CGDirectDisplayID, cameraID: String) async throws {
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized else { throw RecordingError("Camera access is off. Enable Study Timelapse in System Settings → Privacy & Security → Camera, then retry.") }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw RecordingError("Screen recording access is off. Enable Study Timelapse in System Settings → Privacy & Security → Screen & System Audio Recording. If macOS asks, quit and reopen the app.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw RecordingError("The selected display is no longer connected. Refresh devices and select a display.") }
        let selfApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: selfApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = min(1920.0 / Double(display.width), 1080.0 / Double(display.height))
        configuration.width = max(2, Int(Double(display.width) * scale) / 2 * 2)
        configuration.height = max(2, Int(Double(display.height) * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        configuration.showsCursor = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        self.stream = stream
        do {
            try await configureCamera(id: cameraID)
            try await stream.startCapture()
        } catch {
            await stop(); throw error
        }
    }
    private func configureCamera(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cameraQueue.async { [self] in
                do {
                    guard let device = AVCaptureDevice(uniqueID: id) else { throw RecordingError("The selected camera is no longer available.") }
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw RecordingError("Unable to open the camera. Check whether another app is using it.") }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: cameraQueue)
                    guard session.canAddOutput(output) else { throw RecordingError("Unable to receive camera frames.") }
                    session.addOutput(output)
                    session.commitConfiguration()
                    self.session = session
                    let center = NotificationCenter.default
                    observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
                        let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Camera capture stopped."
                        self?.report(detail)
                    })
                    observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in self?.report("Camera capture was interrupted.") })
                    observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in self?.report("The selected camera disconnected.") })
                    session.startRunning()
                    guard session.isRunning else { throw RecordingError("The camera did not start. Close other camera apps and retry.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    public func stop() async {
        markStopped()
        if let stream { try? await stream.stopCapture() }
        stream = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cameraQueue.async { [self] in
                session?.stopRunning(); session = nil
                observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
                continuation.resume()
            }
        }
        clearFrames()
    }
    private func markStopped() { lock.lock(); stopped = true; lock.unlock() }
    private func clearFrames() { lock.lock(); screenFrame = nil; cameraFrame = nil; cameraTime = nil; lock.unlock() }
    public func latestPair(now: Double) -> (CVPixelBuffer, CVPixelBuffer)? {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, FrameFreshness.isUsable(screenAvailable: screenFrame != nil, cameraTime: cameraTime, now: now), let screenFrame, let cameraFrame else { return nil }
        return (screenFrame, cameraFrame)
    }
    private func report(_ message: String) {
        lock.lock()
        let notify = !stopped && !hasReportedError
        hasReportedError = true
        lock.unlock()
        if notify { onError?(message) }
    }
    public func stream(_ stream: SCStream, didStopWithError error: Error) { report("Screen capture stopped: \(error.localizedDescription)") }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let value = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: value) {
            if status == .blank || status == .suspended || status == .stopped {
                report("The screen became unavailable or was locked. The recording has stopped."); return
            }
            guard status == .complete || status == .started else { return }
        }
        guard let image = sampleBuffer.imageBuffer else { return }
        lock.lock(); if !stopped { screenFrame = image }; lock.unlock()
    }
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = sampleBuffer.imageBuffer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if !stopped { cameraFrame = image; cameraTime = now }
        lock.unlock()
    }
}
