/// OptimizerPass.swift
///
/// Copyright 2019, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Seismography

public protocol OptimizerPass: class {
  init()
}

public protocol ScopePass: OptimizerPass {
  func run(on scope: Scope)
}

public protocol ModulePass: OptimizerPass {
  func run(on module: GIRModule)
}
