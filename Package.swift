// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "silt",
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    .package(url: "https://github.com/llvm-swift/FileCheck.git", from: "0.0.4"),
    .package(url: "https://github.com/llvm-swift/Symbolic.git", from: "0.0.1"),
    .package(url: "https://github.com/onevcat/Rainbow.git", from: "3.0.0"),
    .package(url: "https://github.com/llvm-swift/LLVMSwift.git", .branch("master")),
    .package(url: "https://github.com/llvm-swift/Lite.git", from: "0.1.0"),
    .package(url: "https://github.com/llvm-swift/PrettyStackTrace.git", from: "0.0.1"),
  ],
  targets: [
    .target(
      name: "Lithosphere",
      dependencies: ["Rainbow"]),
    .target(
      name: "Crust",
      dependencies: ["Lithosphere"]),
    .target(
      name: "Boring",
      dependencies: ["Drill", "Utility", "Mantle", "Seismography"]),
    .target(
      name: "Drill",
      dependencies: [
        "Lithosphere", "Crust", "Moho", "Mantle", "Seismography",
        "Mesosphere", "OuterCore", "InnerCore", "Utility"
    ]),
    .target(
      name: "silt",
      dependencies: ["Boring", "Utility"],
      swiftSettings: [
        .unsafeFlags([ "-Xlinker", "-w" ], .when(platforms: [.macOS]))
      ]),
    .target(
      name: "SyntaxGen",
      dependencies: ["Utility", "Lithosphere"]),
    .target(
      name: "lite",
      dependencies: ["Symbolic", "LiteSupport", "silt", "Utility"]),
    .target(
      name: "file-check",
      dependencies: ["Drill", "FileCheck", "Utility"]),
    .target(
      name: "Moho",
      dependencies: ["Lithosphere", "Crust", "Utility"]),
    .target(
      name: "Mantle",
      dependencies: ["Lithosphere", "Moho", "Utility", "PrettyStackTrace"]),
    .target(
      name: "Mesosphere",
      dependencies: ["Mantle", "Seismography"]),
    .target(
      name: "OuterCore",
      dependencies: ["Crust", "Seismography", "Utility"]),
    .target(
      name: "Seismography",
      dependencies: ["Moho", "Mantle", "Crust"]),
    .target(
      name: "InnerCore",
      dependencies: ["Crust", "Seismography", "Mesosphere", "OuterCore", "LLVM"],
      swiftSettings: [
        .unsafeFlags([ "-Xlinker", "-w" ], .when(platforms: [.macOS]))
      ]),
    .target(
      name: "Ferrite",
      dependencies: []),
    .testTarget(
      name: "InnerCoreSupportTests",
      dependencies: ["InnerCore"]),
  ]
)
