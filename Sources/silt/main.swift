/// main.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

import Foundation
import Boring

let args = Array(CommandLine.arguments.dropFirst())
let potentialSubtool = args.first ?? ""
switch potentialSubtool {
default:
  SiltFrontendTool(args: args).run()
}
