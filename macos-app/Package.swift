// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shade",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Shade",
            path: "Sources/Shade",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
