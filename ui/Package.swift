// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChronoframeUI",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ChronoframeAppCore", targets: ["ChronoframeAppCore"]),
        .executable(name: "ChronoframeApp", targets: ["ChronoframeApp"]),
    ],
    targets: [
        .target(
            name: "ChronoframeAppCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "ChronoframeApp",
            dependencies: ["ChronoframeAppCore"]
        ),
        .testTarget(
            name: "ChronoframeAppCoreTests",
            dependencies: ["ChronoframeAppCore"],
            path: "Tests/ChronoframeAppCoreTests"
        ),
    ]
)
