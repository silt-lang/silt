// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "silt",
  dependencies: [
    .package(url: "https://github.com/jatoben/CommandLine.git", .branch("master")),
    .package(url: "https://github.com/trill-lang/FileCheck.git", from: "0.0.4"),
    .package(url: "https://github.com/silt-lang/Symbolic.git", from: "0.0.1"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "3.0.0"),
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
      dependencies: ["Lithosphere", "Crust", "Moho", "Mantle"]),
    .target(
      name: "silt",
      dependencies: ["Drill", "CommandLine"]),
    .target(
      name: "SyntaxGen",
      dependencies: ["CommandLine"]),
    .target(
      name: "lite",
      dependencies: ["Drill", "Symbolic", "CommandLine"]),
    .target(
      name: "Moho",
      dependencies: ["Lithosphere", "Crust"]),
    .target(
      name: "Mantle",
      dependencies: ["Lithosphere", "Moho"]),
    .target(
      name: "Seismography",
      dependencies: ["Lithosphere", "Drill"]),
    .testTarget(
      name: "SyntaxTests",
      dependencies: ["Drill", "Lithosphere", "Crust",
                     "Seismography", "FileCheck"]),
    .testTarget(
      name: "DiagnosticTests",
      dependencies: ["Lithosphere", "Seismography"]),
  ]
)
