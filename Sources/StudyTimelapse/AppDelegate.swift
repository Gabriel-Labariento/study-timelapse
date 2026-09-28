import AppKit
import UniformTypeIdentifiers
import TimelapseCore
import TimelapseMedia

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let controller = SessionController()
    private let displayMenu = NSPopUpButton()
    private let cameraMenu = NSPopUpButton()
    private let speedMenu = NSPopUpButton()
    private let sizeMenu = NSPopUpButton()
    private let cornerMenu = NSPopUpButton()
    private var displays: [DisplayChoice] = []
    private var cameras: [CameraChoice] = []
    private let preview = PreviewView()
    private let previewButton = NSButton(title: "Enable preview", target: nil, action: nil)
    private let startButton = NSButton(title: "Start recording…", target: nil, action: nil)
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let finishButton = NSButton(title: "Finish & save", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh devices", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show saved video", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let sessionValue = NSTextField(labelWithString: "00:00:00")
    private let videoValue = NSTextField(labelWithString: "00:00")
    private let stateLabel = NSTextField(labelWithString: "READY TO SET UP")
    private let speedHint = NSTextField(wrappingLabelWithString: "")
    private var observers: [NSObjectProtocol] = []
    private var closeAfterFinish = false
    private var terminateAfterFinish = false
    private let ink = NSColor(calibratedRed: 0.16, green: 0.21, blue: 0.31, alpha: 1)
    private let accent = NSColor(calibratedRed: 0.29, green: 0.39, blue: 0.73, alpha: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Study Timelapse"
        window.minSize = NSSize(width: 1020, height: 770)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.985, alpha: 1)
        window.contentView = BackgroundView()
        buildInterface()
        controller.onChange = { [weak self] in self?.render() }
        controller.onPreview = { [weak self] image in self?.preview.image = image }
        controller.onFinish = { [weak self] result, interruption in self?.finished(result, interruption: interruption) }
        refreshDevices(); render()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.controller.interrupt(reason: "The Mac went to sleep, locked, or switched sessions.") }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
            guard let self, self.displayMenu.indexOfSelectedItem >= 0, self.displayMenu.indexOfSelectedItem < self.displays.count else { return }
            let id = self.displays[self.displayMenu.indexOfSelectedItem].id
            if !CaptureSources.displays().contains(where: { $0.id == id }) {
                self.controller.interrupt(reason: "The selected display disconnected.")
            }
            }
        })
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--ui-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.saveUICheck() }
        }
    }
    private func makeMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); menu.addItem(app)
        let submenu = NSMenu(); app.submenu = submenu
        submenu.addItem(withTitle: "About Study Timelapse", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Hide Study Timelapse", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        submenu.addItem(withTitle: "Quit Study Timelapse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "Edit")
        edit.submenu?.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color ?? ink
        return label
    }
    private func stack(_ views: [NSView], vertical: Bool, spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = vertical ? .vertical : .horizontal
        stack.spacing = spacing; stack.alignment = vertical ? .leading : .centerY
        return stack
    }
    private func spacer() -> NSView { let view = NSView(); view.setContentHuggingPriority(.init(1), for: .horizontal); return view }
    private func field(_ title: String, _ control: NSPopUpButton) -> NSView {
        control.controlSize = .large; control.font = .systemFont(ofSize: 13)
        let field = stack([label(title, size: 11, weight: .semibold, color: .secondaryLabelColor), control], vertical: true, spacing: 5)
        control.widthAnchor.constraint(equalTo: field.widthAnchor).isActive = true
        return field
    }
    private func counter(_ title: String, _ value: NSTextField) -> NSView {
        value.font = .monospacedDigitSystemFont(ofSize: 27, weight: .medium); value.textColor = ink
        return stack([label(title, size: 11, weight: .medium, color: .secondaryLabelColor), value], vertical: true, spacing: 6)
    }
    private func buildInterface() {
        guard let content = window.contentView else { return }
        let title = label("Study Timelapse", size: 29, weight: .semibold)
        let subtitle = label("A little record of time well spent.", size: 14, color: .secondaryLabelColor)
        let heading = stack([title, subtitle], vertical: true, spacing: 5)
        let header = stack([heading, spacer(), label("LOCAL VIDEO  ·  NO AUDIO", size: 10, weight: .semibold, color: accent)], vertical: false)
        stateLabel.font = .systemFont(ofSize: 10, weight: .bold); stateLabel.textColor = accent
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 9/16).isActive = true
        let counters = stack([counter("STUDY TIME", sessionValue), spacer(), counter("VIDEO LENGTH", videoValue)], vertical: false)
        let caption = label("Your screen fills the video. Your camera stays in the corner.", size: 12, color: .secondaryLabelColor)
        let left = stack([stateLabel, preview, counters, caption], vertical: true, spacing: 15)
        for item in [preview, counters] { item.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true }

        speedMenu.addItems(withTitles: ["10× · gently sped up", "30× · study session", "60× · a quick recap"]); speedMenu.selectItem(at: 1)
        sizeMenu.addItems(withTitles: ["Small", "Medium", "Large"]); sizeMenu.selectItem(at: 1)
        cornerMenu.addItems(withTitles: InsetCorner.allCases.map(\.rawValue)); cornerMenu.selectItem(at: 3)
        for control in [displayMenu, cameraMenu] { control.target = self; control.action = #selector(sourceChanged) }
        for control in [speedMenu, sizeMenu, cornerMenu] { control.target = self; control.action = #selector(settingsChanged) }
        speedHint.font = .systemFont(ofSize: 12); speedHint.textColor = .secondaryLabelColor
        refreshButton.target = self; refreshButton.action = #selector(refreshDevices)
        refreshButton.bezelStyle = .inline; refreshButton.font = .systemFont(ofSize: 11)
        let sidebarFields = [field("SCREEN", displayMenu), field("CAMERA", cameraMenu), field("TIMELAPSE SPEED", speedMenu), field("CAMERA SIZE", sizeMenu), field("CAMERA POSITION", cornerMenu)]
        let sidebar = stack(sidebarFields + [speedHint, refreshButton], vertical: true, spacing: 13)
        sidebar.widthAnchor.constraint(equalToConstant: 258).isActive = true
        for view in sidebarFields + [speedHint] { view.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true }
        let body = stack([left, sidebar], vertical: false, spacing: 28); body.alignment = .top
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 610).isActive = true
        let divider = NSBox(); divider.boxType = .separator
        statusLabel.font = .systemFont(ofSize: 13); statusLabel.textColor = ink
        statusLabel.maximumNumberOfLines = 4
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let settingsButton = NSButton(title: "Permissions…", target: self, action: #selector(openPermissions))
        settingsButton.bezelStyle = .inline; settingsButton.font = .systemFont(ofSize: 11)
        revealButton.target = self; revealButton.action = #selector(revealMovie); revealButton.bezelStyle = .inline
        let statusRow = stack([statusLabel, spacer(), revealButton, settingsButton], vertical: false, spacing: 16)
        statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 720).isActive = true
        for button in [previewButton, startButton, pauseButton, finishButton] { button.bezelStyle = .rounded; button.controlSize = .large; button.target = self }
        previewButton.action = #selector(togglePreview); startButton.action = #selector(startRecording)
        pauseButton.action = #selector(pauseRecording); finishButton.action = #selector(finishRecording)
        startButton.bezelColor = accent; startButton.contentTintColor = .white
        startButton.keyEquivalent = "r"; startButton.keyEquivalentModifierMask = [.command]
        let buttons = stack([previewButton, spacer(), pauseButton, finishButton, startButton], vertical: false, spacing: 12)
        let root = stack([header, body, divider, statusRow, buttons], vertical: true, spacing: 22)
        root.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 25),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])
        for view in [header, body, divider, statusRow, buttons] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        settingsChanged()
    }
    @objc private func refreshDevices() {
        guard !controller.isBusy, !controller.loading, !controller.stopping else { return }
        let previousDisplay = displayMenu.indexOfSelectedItem >= 0 && displayMenu.indexOfSelectedItem < displays.count ? displays[displayMenu.indexOfSelectedItem].id : nil
        let previousCamera = cameraMenu.indexOfSelectedItem >= 0 && cameraMenu.indexOfSelectedItem < cameras.count ? cameras[cameraMenu.indexOfSelectedItem].id : nil
        if controller.previewReady { controller.disablePreview() }
        displays = CaptureSources.displays(); cameras = CaptureSources.cameras()
        displayMenu.removeAllItems(); cameraMenu.removeAllItems()
        displayMenu.addItems(withTitles: displays.map(\.name)); cameraMenu.addItems(withTitles: cameras.map(\.name))
        if let index = displays.firstIndex(where: { $0.id == previousDisplay }) { displayMenu.selectItem(at: index) }
        if let index = cameras.firstIndex(where: { $0.id == previousCamera }) { cameraMenu.selectItem(at: index) }
        render()
    }
    private var settings: RecordingSettings {
        RecordingSettings(speed: [10, 30, 60][max(0, speedMenu.indexOfSelectedItem)],
            corner: InsetCorner.allCases[max(0, cornerMenu.indexOfSelectedItem)],
            insetFraction: [0.20, 0.28, 0.36][max(0, sizeMenu.indexOfSelectedItem)])
    }
    @objc private func sourceChanged() { controller.disablePreview() }
    @objc private func settingsChanged() {
        let minutes = 60.0 / Double(settings.speed)
        speedHint.stringValue = "1 hour of studying → \(minutes.formatted(.number.precision(.fractionLength(0...1)))) min of video.\n1080p · MP4 · 30 fps"
        controller.update(settings: settings)
    }
    @objc private func togglePreview() {
        if controller.previewReady { controller.disablePreview(); return }
        guard displays.indices.contains(displayMenu.indexOfSelectedItem), cameras.indices.contains(cameraMenu.indexOfSelectedItem) else { return }
        controller.enablePreview(display: displays[displayMenu.indexOfSelectedItem].id, camera: cameras[cameraMenu.indexOfSelectedItem].id, settings: settings)
    }
    @objc private func startRecording() {
        guard controller.previewReady, !controller.isBusy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]
        panel.title = "Save your study timelapse"; panel.prompt = "Start recording"
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm"
        panel.nameFieldStringValue = "Study \(formatter.string(from: Date())).mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.startAtDestination(url)
        }
    }
    private func startAtDestination(_ url: URL) {
        let decision = DestinationPolicy.saveDecision(existsNow: FileManager.default.fileExists(atPath: url.path), confirmation: nil)
        switch decision {
        case .start(let replace): controller.start(destination: url, replaceExisting: replace)
        case .cancel: return
        case .confirmReplacement:
            // A destination may have appeared after the save panel checked it. Existence is not consent.
            let alert = NSAlert()
            alert.messageText = "Replace this existing video?"
            alert.informativeText = "\(url.lastPathComponent) already exists. It will be replaced only after the new recording is successfully finished."
            alert.addButton(withTitle: "Replace after recording")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                let approved = response == .alertFirstButtonReturn
                if case .start(let replace) = DestinationPolicy.saveDecision(existsNow: true, confirmation: approved) {
                    self?.controller.start(destination: url, replaceExisting: replace)
                }
            }
        }
    }
    @objc private func pauseRecording() { controller.pauseOrResume() }
    @objc private func finishRecording() { controller.finish() }
    @objc private func revealMovie() { if let url = controller.savedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }
    private func render() {
        let available = !controller.isBusy && !controller.loading && !controller.stopping
        for control in [displayMenu, cameraMenu, speedMenu, sizeMenu, cornerMenu] { control.isEnabled = available }
        refreshButton.isEnabled = available
        previewButton.isEnabled = available && !displays.isEmpty && !cameras.isEmpty
        previewButton.title = controller.loading ? "Opening preview…" : controller.stopping ? "Closing preview…" : controller.previewReady ? "Turn preview off" : "Enable preview"
        startButton.isEnabled = controller.previewReady && available
        pauseButton.isEnabled = controller.state == .recording || controller.state == .paused
        pauseButton.title = controller.state == .paused ? "Resume" : "Pause"
        finishButton.isEnabled = controller.state == .recording || controller.state == .paused
        revealButton.isHidden = controller.savedURL == nil
        statusLabel.stringValue = cameras.isEmpty ? "No camera found. Connect or enable a camera, then refresh devices." : controller.status
        stateLabel.stringValue = controller.isBusy ? (controller.state == .recording ? "● RECORDING" : controller.state.rawValue.uppercased()) : controller.previewReady ? "LIVE PREVIEW · NOT RECORDING" : "READY TO SET UP"
        stateLabel.textColor = controller.state == .recording ? .systemRed : accent
        sessionValue.stringValue = Self.duration(controller.elapsed, hours: true)
        videoValue.stringValue = Self.duration(Double(controller.frames)/30, hours: false)
    }
    static func duration(_ seconds: Double, hours: Bool) -> String {
        let total = max(0, Int(seconds))
        return hours || total >= 3600 ? String(format: "%02d:%02d:%02d", total/3600, (total/60)%60, total%60) : String(format: "%02d:%02d", total/60, total%60)
    }
    private func finished(_ result: Result<URL, Error>, interruption: String?) {
        if case .failure(let error) = result {
            let alert = NSAlert(); alert.messageText = "The video could not be saved"; alert.informativeText = error.localizedDescription; alert.runModal()
        } else if let interruption {
            let alert = NSAlert(); alert.messageText = "Session interrupted"; alert.informativeText = interruption + "\nThe completed portion was saved."; alert.runModal()
        }
        if terminateAfterFinish { NSApp.reply(toApplicationShouldTerminate: true) }
        else if closeAfterFinish { closeAfterFinish = false; window.performClose(nil) }
    }
    private func confirmFinish() -> Bool {
        let alert = NSAlert(); alert.messageText = "Finish your study session?"
        alert.informativeText = "Your recording will be saved before the app closes."
        alert.addButton(withTitle: "Finish & save"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if controller.isBusy {
            if controller.state == .finishing { return false }
            if confirmFinish() { closeAfterFinish = true; controller.finish() }
            return false
        }
        controller.disablePreview(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if controller.isBusy {
            guard controller.state != .finishing, confirmFinish() else { return .terminateCancel }
            terminateAfterFinish = true; controller.finish(); return .terminateLater
        }
        controller.disablePreview(); return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func saveUICheck() {
        guard let index = CommandLine.arguments.firstIndex(of: "--ui-check"), CommandLine.arguments.indices.contains(index+1), let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1])) }
        NSApp.terminate(nil)
    }
}

@MainActor final class PreviewView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    override init(frame: NSRect) { super.init(frame: frame); setAccessibilityLabel("Composed screen and camera preview") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    convenience init() { self.init(frame: .zero) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.13, green: 0.18, blue: 0.27, alpha: 1).setFill(); path.fill()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if let image {
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)).draw(in: bounds)
        } else {
            let icon = NSImage(systemSymbolName: "rectangle.inset.filled.and.person.filled", accessibilityDescription: nil) ?? NSImage(systemSymbolName: "video", accessibilityDescription: nil)
            let tintedIcon = icon?.withSymbolConfiguration(.init(paletteColors: [.white.withAlphaComponent(0.65)]))
            tintedIcon?.draw(in: NSRect(x: bounds.midX-22, y: bounds.midY+28, width: 44, height: 36))
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let title = "Make room for a focused session."
            title.draw(in: NSRect(x: 20, y: bounds.midY-8, width: bounds.width-40, height: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
            let subtitle = "Enable preview to see your screen and camera together."
            subtitle.draw(in: NSRect(x: 20, y: bounds.midY-42, width: bounds.width-40, height: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1), .paragraphStyle: paragraph])
            let box = NSRect(x: bounds.width-140, y: 16, width: 124, height: 82)
            NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.43, alpha: 1).setFill(); NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            "CAMERA".draw(in: NSRect(x: box.minX, y: box.midY-7, width: box.width, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1), .paragraphStyle: paragraph])
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor final class BackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.95, green: 0.965, blue: 0.985, alpha: 1).setFill()
        bounds.fill()
    }
}
