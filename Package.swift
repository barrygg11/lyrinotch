// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Lyrinotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LyrinotchCore", targets: ["LyrinotchCore"]),
        .executable(name: "Lyrinotch", targets: ["Lyrinotch"])
    ],
    targets: [
        .target(
            name: "LyrinotchCore",
            path: "Sources/LyrinotchCore"
        ),
        .executableTarget(
            name: "Lyrinotch",
            dependencies: ["LyrinotchCore"],
            path: "Sources/Lyrinotch",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "LyrinotchTests",
            dependencies: ["LyrinotchCore", "Lyrinotch"],
            path: "Tests/LyrinotchTests"
        )
    ]
)
