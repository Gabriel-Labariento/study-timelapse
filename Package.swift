// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "StudyTimelapse",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "StudyTimelapse", targets: ["StudyTimelapse"])],
    targets: [
        .target(name: "TimelapseCore"),
        .target(name: "TimelapseMedia", dependencies: ["TimelapseCore"]),
        .executableTarget(name: "StudyTimelapse", dependencies: ["TimelapseCore", "TimelapseMedia"]),
        .executableTarget(name: "CoreChecks", dependencies: ["TimelapseCore"], path: "Tests/TimelapseCoreTests"),
        .executableTarget(name: "MediaChecks", dependencies: ["TimelapseCore", "TimelapseMedia"], path: "Tests/TimelapseMediaTests")
    ],
    swiftLanguageModes: [.v5]
)
