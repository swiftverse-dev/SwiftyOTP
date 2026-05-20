// swift-tools-version: 6.2

import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    // Approachable concurrency — relaxes strict mode so half-migrated states compile.
    // Re-tightened to StrictConcurrency in Phase 4 (cutover).
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
]

let package = Package(
    name: "SwiftyOTP",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwiftyOTP", targets: ["SwiftyOTP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/norio-nomura/Base32.git", exact: "0.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-clocks.git", exact: "1.0.6")
    ],
    targets: [
        .target(
            name: "SwiftyOTP",
            dependencies: [
                "Base32",
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: upcomingFeatures
        ),
        .testTarget(
            name: "SwiftyOTPTests",
            dependencies: [
                "SwiftyOTP",
                .product(name: "Clocks", package: "swift-clocks"),
            ],
            swiftSettings: upcomingFeatures
        ),
    ],
    // Temporarily on .v5 during the swift-6 migration: the legacy Combine
    // `Countdown.start()` captures a local `var lastWindow` in its `Timer`
    // closure, which Swift 6 mode rejects. The Phase 5 cutover deletes the
    // legacy file and restores `.v6` together with `StrictConcurrency`.
    swiftLanguageModes: [.v5]
)
