import AppKit
import IOKit.pwr_mgt
import TimelapseCore
import TimelapseMedia

@MainActor final class SessionController {
    private(set) var state = SessionState.idle
    private(set) var previewReady = false
    private(set) var loading = false
    private(set) var stopping = false
    private(set) var elapsed = 0.0
    private(set) var frames: Int64 = 0
    private(set) var status = "Choose your screen and camera, then enable the preview."
    private(set) var savedURL: URL?
    var onChange: (() -> Void)?
    var onPreview: ((CGImage?) -> Void)?
    var onFinish: ((Result<URL, Error>, String?) -> Void)?
    private var previewVisible = true
    private var sources: CaptureSources?
    private var engine: RecordingEngine?
    private var setupTask: Task<Void, Never>?
    private var generation = UUID()
    private var assertion: IOPMAssertionID = 0
    private var ownsAssertion = false
    private var interruption: String?
    var isBusy: Bool { state.isBusy }

    func enablePreview(display: CGDirectDisplayID, camera: String, settings: RecordingSettings) {
        guard !isBusy, !loading, !stopping, sources == nil else { return }
        loading = true; previewReady = false; savedURL = nil
        status = "Opening the screen and camera…"; onChange?()
        let token = UUID(); generation = token
        let source = CaptureSources(); sources = source
        source.onError = { [weak self] message in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.interrupt(reason: message)
            }
        }
        setupTask = Task { [weak self] in
            do {
                try await source.start(displayID: display, cameraID: camera)
                guard let self, self.generation == token else { return }
                let engine = RecordingEngine(sources: source, settings: settings, onSnapshot: { [weak self] snapshot in
                    guard let self, self.generation == token else { return }
                    let first = !self.previewReady
                    self.previewReady = true; self.loading = false
                    self.elapsed = snapshot.elapsed; self.frames = snapshot.frames
                    if first { self.status = "Preview is live. Choose Start recording when you’re ready." }
                    if self.previewVisible, let image = snapshot.image { self.onPreview?(image) }
                    self.onChange?()
                }, onError: { [weak self] message in
                    guard let self, self.generation == token else { return }
                    self.interrupt(reason: message)
                })
                self.engine = engine; engine.setPreviewVisible(self.previewVisible); engine.startPreview()
            } catch {
                guard let self, self.generation == token else { return }
                self.status = error.localizedDescription
                self.disablePreview(keepStatus: true)
            }
        }
    }
    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        engine?.setPreviewVisible(visible)
    }
    func update(settings: RecordingSettings) { guard !isBusy else { return }; engine?.update(settings: settings) }
    func disablePreview(keepStatus: Bool = false) {
        guard !isBusy else { return }
        generation = UUID()
        engine?.shutdown(); engine = nil
        let source = sources; sources = nil
        let pending = setupTask; setupTask = nil
        previewReady = false; loading = false
        if !keepStatus { status = "Preview is off. Enable it to set up your next session." }
        onPreview?(nil)
        stopping = source != nil
        onChange?()
        Task { [weak self] in
            await pending?.value
            await source?.stop()
            self?.stopping = false; self?.onChange?()
        }
    }
    func start(destination: URL, replaceExisting: Bool) {
        guard previewReady, let engine, state.transition(to: .preparing) else { return }
        interruption = nil; elapsed = 0; frames = 0; savedURL = nil
        status = "Preparing your video…"; onChange?()
        engine.startRecording(destination: destination, replaceExisting: replaceExisting) { [weak self] result in
            guard let self, self.state == .preparing else { return }
            switch result {
            case .success:
                self.state.transition(to: .recording); self.preventSleep()
                self.status = "Recording your study session."
            case .failure(let error):
                self.state.transition(to: .error); self.status = error.localizedDescription
            }
            self.onChange?()
        }
    }
    func pauseOrResume() {
        if state == .recording {
            state.transition(to: .paused); engine?.pause { [weak self] in self?.onChange?() }; releaseSleep()
            status = "Paused. This time is excluded from the video."
        } else if state == .paused {
            state.transition(to: .recording); engine?.resume(); preventSleep()
            status = "Recording your study session."
        }
        onChange?()
    }
    func finish() {
        guard state.transition(to: .finishing) else { return }
        releaseSleep(); status = "Finishing and saving your video…"; onChange?()
        engine?.finish { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.savedURL = url; self.state.transition(to: .idle)
                self.status = self.interruption == nil ? "Saved \(url.lastPathComponent)" : "Session interrupted. Saved the completed portion: \(url.lastPathComponent)"
            case .failure(let error):
                self.state.transition(to: .error); self.status = error.localizedDescription
            }
            self.disablePreview(keepStatus: true)
            self.onFinish?(result, self.interruption)
        }
    }
    func interrupt(reason: String) {
        if state == .finishing { return }
        if isBusy { interruption = reason; finish() }
        else { status = reason; disablePreview(keepStatus: true) }
    }
    private func preventSleep() {
        guard !ownsAssertion else { return }
        ownsAssertion = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Study Timelapse recording" as CFString, &assertion) == kIOReturnSuccess
    }
    private func releaseSleep() {
        if ownsAssertion { IOPMAssertionRelease(assertion); ownsAssertion = false }
    }
}
