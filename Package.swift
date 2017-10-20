// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "silt",
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/jatoben/CommandLine.git", .branch("master")),
    .package(url: "https://github.com/trill-lang/FileCheck.git", .branch("master")),
    .package(url: "https://github.com/onevcat/Rainbow", from: "3.0.0"),
    ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages which this package depends on.
    .target(
      name: "Lithosphere",
      dependencies: ["Rainbow"]),
    .target(
      name: "Crust",
      dependencies: ["Lithosphere"]),
    .target(
      name: "Drill",
      dependencies: ["Lithosphere", "Crust"]),
    .target(
      name: "silt",
      dependencies: ["Drill", "CommandLine"]),
    .target(
      name: "SyntaxGen",
      dependencies: ["CommandLine"]),

    .testTarget(
      name: "SyntaxTests",
      dependencies: ["Lithosphere", "Crust", "FileCheck"]),
    .testTarget(
      name: "DiagnosticTests",
      dependencies: ["Lithosphere"]),
    ]
)
