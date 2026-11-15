// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "xcprojgen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "xcprojgen", targets: ["xcprojgen"]),
        .library(name: "XCProjGenKit", targets: ["XCProjGenKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/xcode-project-format", exact: "0.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .target(
            name: "PklRuntimeResources",
            path: "Pkl",
            exclude: [
                "xcproj/PklProject", "xcproj/Project.pkl", "xcproj/Workspace.pkl",
                "xcproj/README.md",
                "xcproj/tests",
            ],
            sources: ["RuntimeResources.swift"],
            resources: [.copy("xcproj/Internal")]
        ),
        .target(
            name: "XCProjGenKit",
            dependencies: [
                "PklRuntimeResources",
                .product(name: "XcodeProjectFormat", package: "xcode-project-format"),
            ]),
        .executableTarget(
            name: "xcprojgen",
            dependencies: [
                "XCProjGenKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(
            name: "XCProjGenKitTests",
            dependencies: [
                "XCProjGenKit",
                .product(name: "XcodeProjectFormat", package: "xcode-project-format"),
            ]),
    ]
)
