// swift-tools-version: 6.2
import PackageDescription

// The script links the production sources and the same tests used by the app.
let package = Package(
    name: "SourceMicrophoneVerification",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RemoteMic"),
        .testTarget(name: "RemoteMicTests", dependencies: ["RemoteMic"]),
    ],
    swiftLanguageModes: [.v5]
)
