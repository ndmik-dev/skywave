// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Skywave",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SkywaveKit",
            path: "Sources/SkywaveKit",
            resources: [.process("Resources")]
        ),
        // Phase 0 harness: endurance-tests AVPlayer against endless Icecast.
        .executableTarget(
            name: "Probe",
            dependencies: ["SkywaveKit"],
            path: "Sources/Probe"
        ),
        // XCTest and swift-testing both ship with Xcode, which this setup does
        // not have, so the checks are a plain executable instead.
        .executableTarget(
            name: "Checks",
            dependencies: ["SkywaveKit"],
            path: "Sources/Checks"
        ),
    ]
)
