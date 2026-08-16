// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltTabClone",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AltTabClone",
            path: "Sources/AltTabClone",
            // Swift 5 language mode: the Accessibility C APIs are not Sendable-annotated,
            // and strict concurrency adds no safety for this single-threaded probe.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
