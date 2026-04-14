// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProvidenceOverlay",
    platforms: [.macOS(.v14)],  // 14.0+ for modern SwiftUI/NSPanel APIs
    products: [
        .executable(name: "providence-overlay", targets: ["ProvidenceOverlay"]),
        .library(name: "ProvidenceOverlayCore", targets: ["ProvidenceOverlayCore"]),
    ],
    targets: [
        .executableTarget(
            name: "ProvidenceOverlay",
            dependencies: ["ProvidenceOverlayCore"],
            path: "Sources/ProvidenceOverlay",
            resources: []
        ),
        .target(
            name: "ProvidenceOverlayCore",
            path: "Sources/ProvidenceOverlayCore"
        ),
        .testTarget(
            name: "ProvidenceOverlayCoreTests",
            dependencies: ["ProvidenceOverlayCore"],
            path: "Tests/ProvidenceOverlayCoreTests"
        ),
    ]
)
