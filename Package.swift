// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "silt",
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    .package(url: "https://github.com/trill-lang/FileCheck.git", from: "0.0.4"),
    .package(url: "https://github.com/silt-lang/Symbolic.git", from: "0.0.1"),
    .package(url: "https://github.com/onevcat/Rainbow.git", from: "3.0.0"),
    .package(url: "https://github.com/silt-lang/Lite.git", from: "0.0.3"),
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
      dependencies: ["Lithosphere", "Crust", "Moho", "Mantle", "Utility"]),
    .target(
      name: "silt",
      dependencies: ["Drill", "Utility"]),
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
      dependencies: ["Lithosphere", "Moho"]),
  ]
)
