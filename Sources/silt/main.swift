/// main.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Boring

let args = Array(CommandLine.arguments.dropFirst())
let potentialSubtool = args.first ?? ""
switch potentialSubtool {
case "demangle":
  SiltDemangleTool(Array(args.dropFirst())).run()
case "optimize":
  SiltOptimizeTool(Array(args.dropFirst())).run()
default:
  SiltFrontendTool(args: args).run()
}
