// swift-tools-version: 6.2

import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
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
    swiftLanguageModes: [.v6]
)
