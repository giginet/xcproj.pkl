// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "xcproj-pkl",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "xcproj-pkl", targets: ["XcprojPklCLI"]),
    .library(name: "XcprojPkl", targets: ["XcprojPkl"]),
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
        "xcproj/PklProject", "xcproj/Project.pkl", "xcproj/Workspace.pkl", "xcproj/README.md",
        "xcproj/tests",
      ],
      sources: ["RuntimeResources.swift"],
      resources: [.copy("xcproj/Internal")]
    ),
    .target(
      name: "XcprojPkl",
      dependencies: [
        "PklRuntimeResources",
        .product(name: "XcodeProjectFormat", package: "xcode-project-format"),
      ]),
    .executableTarget(
      name: "XcprojPklCLI",
      dependencies: [
        "XcprojPkl",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]),
    .testTarget(
      name: "XcprojPklTests",
      dependencies: [
        "XcprojPkl",
        .product(name: "XcodeProjectFormat", package: "xcode-project-format"),
      ]),
  ]
)
