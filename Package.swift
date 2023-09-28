// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftyOTP",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(name: "SwiftyOTP", targets: ["SwiftyOTP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/norio-nomura/Base32.git", from: "0.9.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "SwiftyOTP", dependencies: ["Base32"]),
        .testTarget(
            name: "SwiftyOTPTests",
            dependencies: ["SwiftyOTP"]),
    ]
)
