// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProvidenceOverlay",
    platforms: [.macOS("15.4")],  // mlx-swift-audio requires 15.4+
    products: [
        .executable(name: "providence-overlay", targets: ["ProvidenceOverlay"]),
        .library(name: "ProvidenceOverlayCore", targets: ["ProvidenceOverlayCore"]),
    ],
    dependencies: [
        // Using alxxpersonal fork: DePasqualeOrg/mlx-swift-audio's upstream
        // pins swift-tokenizers-mlx on branch `main`, but that branch's tip
        // (e354599) bumped mlx-swift-lm to a revision that conflicts with
        // mlx-swift-audio's own pin (8c9dd63). The fork pins tokenizers to
        // 77bb1b1 which agrees. File upstream PR once confirmed working.
        .package(url: "https://github.com/alxxpersonal/mlx-swift-audio", branch: "fix-tokenizers-pin"),
    ],
    targets: [
        .executableTarget(
            name: "ProvidenceOverlay",
            dependencies: [
                "ProvidenceOverlayCore",
                .product(name: "MLXAudio", package: "mlx-swift-audio"),
            ],
            path: "Sources/ProvidenceOverlay",
            resources: [],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .target(
            name: "ProvidenceOverlayCore",
            path: "Sources/ProvidenceOverlayCore",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ProvidenceOverlayCoreTests",
            dependencies: ["ProvidenceOverlayCore"],
            path: "Tests/ProvidenceOverlayCoreTests"
        ),
    ]
)
