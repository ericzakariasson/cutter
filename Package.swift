// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cutter",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: actions, frame math, shortcut model. No AppKit, fully unit-tested.
        .target(
            name: "CutterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app. `scripts/build-app.sh` wraps this binary in Cutter.app.
        .executableTarget(
            name: "Cutter",
            dependencies: ["CutterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Draws the README's demo clip off-screen. Run it with scripts/make-demo.sh.
        .executableTarget(
            name: "CutterDemo",
            dependencies: ["CutterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CutterCoreTests",
            dependencies: ["CutterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CutterDemoTests",
            dependencies: ["CutterDemo", "CutterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CutterTests",
            dependencies: ["Cutter", "CutterCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
