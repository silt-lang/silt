/// PassTimer.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

class PassTimer {
  private var timings = [(String, TimeInterval)]()

  func measure<Out>(pass: String, actions: () -> Out) -> Out {
    let start = CFAbsoluteTimeGetCurrent()
    defer {
      let end = CFAbsoluteTimeGetCurrent()
      timings.append((pass, end - start))
    }
    return actions()
  }
}
