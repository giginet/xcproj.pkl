// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AdvancedSupportPackage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AdvancedSupport", targets: ["SupportCore"])
    ],
    targets: [
        .target(name: "SupportCore")
    ]
)
