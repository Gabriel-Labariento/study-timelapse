import AppKit
import TimelapseMedia

@main struct StudyTimelapseApplication {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--verify-export"), CommandLine.arguments.indices.contains(index+1) {
            let destination = URL(fileURLWithPath: CommandLine.arguments[index+1])
            Task {
                do { try await SyntheticExport.run(to: destination); exit(0) }
                catch { fputs("Verification failed: \(error.localizedDescription)\n", stderr); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
