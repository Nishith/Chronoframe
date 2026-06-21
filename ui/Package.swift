// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChronoframeUI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChronoframeCore", targets: ["ChronoframeCore"]),
        .library(name: "ChronoframeAppCore", targets: ["ChronoframeAppCore"]),
        .library(name: "ChronoframeCLIKit", targets: ["ChronoframeCLIKit"]),
        .library(name: "ChronoframePackaging", targets: ["ChronoframePackaging"]),
        .executable(name: "ChronoframeApp", targets: ["ChronoframeApp"]),
        .executable(name: "ChronoframeCLI", targets: ["ChronoframeCLI"]),
        .executable(name: "ChronoframePackagingTool", targets: ["ChronoframePackagingTool"]),
        .executable(name: "ChronoframeIconTool", targets: ["ChronoframeIconTool"]),
        .executable(name: "ChronoframeVideoCalibrationTool", targets: ["ChronoframeVideoCalibrationTool"]),
    ],
    targets: [
        .target(
            name: "ChronoframeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "ChronoframeAppCore",
            dependencies: ["ChronoframeCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "ChronoframeCLIKit",
            dependencies: ["ChronoframeAppCore", "ChronoframeCore"]
        ),
        .target(
            name: "ChronoframePackaging"
        ),
        .executableTarget(
            name: "ChronoframeApp",
            dependencies: ["ChronoframeAppCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ChronoframeCLI",
            dependencies: ["ChronoframeCLIKit"]
        ),
        .executableTarget(
            name: "ChronoframePackagingTool",
            dependencies: ["ChronoframePackaging"]
        ),
        // Procedural renderer for the macOS app icon. Run via
        // `swift run ChronoframeIconTool <output-dir>` to regenerate every
        // PNG variant (Any / Dark / Tinted × all sizes) for the
        // `Assets.xcassets/AppIcon.appiconset`. The tool is the single
        // source of truth for the icon design — colors and geometry live
        // in code, not in a Sketch/Figma file.
        .executableTarget(
            name: "ChronoframeIconTool"
        ),
        // Offline perceptual-video calibration harness (Milestone 2c). Local
        // only — consumes an external labeled corpus manifest and prints
        // precision/recall/throughput/stability metrics. Deliberately out of
        // CI (no corpus in the repo); see docs/video-dedupe-calibration-rubric.md.
        .executableTarget(
            name: "ChronoframeVideoCalibrationTool",
            dependencies: ["ChronoframeCore"]
        ),
        .testTarget(
            name: "ChronoframeAppCoreTests",
            dependencies: ["ChronoframeAppCore", "ChronoframeCore"],
            path: "Tests/ChronoframeAppCoreTests",
            exclude: ["Fixtures", "mock_print.txt"]
        ),
        .testTarget(
            name: "ChronoframeAppTests",
            dependencies: ["ChronoframeApp"],
            path: "Tests/ChronoframeAppTests"
        ),
        .testTarget(
            name: "ChronoframeCLIKitTests",
            // Depending on the executable target forces SwiftPM to
            // build the CLI binary as part of `swift test`, which lets
            // the subprocess-boundary regression tests exec it directly
            // (PHASE2_FINDINGS.md NEW15).
            dependencies: ["ChronoframeCLIKit", "ChronoframeCLI", "ChronoframeCore"],
            path: "Tests/ChronoframeCLIKitTests"
        ),
        .testTarget(
            name: "ChronoframePackagingTests",
            dependencies: ["ChronoframePackaging"],
            path: "Tests/ChronoframePackagingTests"
        ),
    ]
)
