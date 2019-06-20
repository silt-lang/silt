// swift-tools-version:5.0

import PackageDescription

let package = Package(
  name: "silt",
  platforms: [
    .macOS(.v10_14)
  ],
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
      dependencies: ["Drill", "SPMUtility", "Mantle", "Seismography"]),
    .target(
      name: "Drill",
      dependencies: [
        "Lithosphere", "Crust", "Moho", "Mantle", "Seismography",
        "Mesosphere", "OuterCore", "InnerCore", "SPMUtility"
    ]),
    .target(
      name: "silt",
      dependencies: ["Boring", "SPMUtility"]),
    .target(
      name: "SyntaxGen",
      dependencies: ["SPMUtility", "Lithosphere"]),
    .target(
      name: "lite",
      dependencies: ["Symbolic", "LiteSupport", "silt", "SPMUtility"]),
    .target(
      name: "file-check",
      dependencies: ["Drill", "FileCheck", "SPMUtility"]),
    .target(
      name: "Moho",
      dependencies: ["Lithosphere", "Crust", "SPMUtility"]),
    .target(
      name: "Mantle",
      dependencies: ["Lithosphere", "Moho", "SPMUtility", "PrettyStackTrace"]),
    .target(
      name: "Mesosphere",
      dependencies: ["Mantle", "Seismography"]),
    .target(
      name: "OuterCore",
      dependencies: ["Crust", "Seismography", "SPMUtility"]),
    .target(
      name: "Seismography",
      dependencies: ["Moho", "Mantle", "Crust"]),
    .target(
      name: "InnerCore",
      dependencies: ["Crust", "Seismography", "Mesosphere", "OuterCore", "LLVM"]),
    .target(
      name: "Ferrite",
      dependencies: []),
    .testTarget(
      name: "InnerCoreSupportTests",
      dependencies: ["InnerCore"]),
  ],
  cxxLanguageStandard: .cxx14
)
