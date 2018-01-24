// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "silt",
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    .package(url: "https://github.com/llvm-swift/FileCheck.git", from: "0.0.4"),
    .package(url: "https://github.com/llvm-swift/Symbolic.git", from: "0.0.1"),
    .package(url: "https://github.com/onevcat/Rainbow.git", from: "3.0.0"),
    .package(url: "https://github.com/llvm-swift/Lite.git", from: "0.0.3"),
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
      name: "Drill",
      dependencies: ["Lithosphere", "Crust", "Moho", "Mantle", "Utility", "OuterCore"]),
    .target(
      name: "silt",
      dependencies: ["Drill", "Utility", "Runtime"]),
    .target(
      name: "SyntaxGen",
      dependencies: ["Utility"]),
    .target(
      name: "lite",
      dependencies: ["Symbolic", "LiteSupport", "silt", "Utility"]),
    .target(
      name: "file-check",
      dependencies: ["Drill", "FileCheck", "Utility"]),
    .target(
      name: "Moho",
      dependencies: ["Lithosphere", "Crust"]),
    .target(
      name: "Mantle",
      dependencies: ["Lithosphere", "Moho", "Utility", "PrettyStackTrace"]),
    .target(
      name: "Runtime",
      dependencies: []),
    .target(
      name: "OuterCore",
      dependencies: ["Crust", "Moho", "Mantle", "Runtime"]),
  ],
  cxxLanguageStandard: .cxx14
)
