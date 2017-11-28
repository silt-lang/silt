/// PassTimer.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

class PassTimer {
  private var timings = [(String, TimeInterval)]()
  private var currentPass: String?
  private var currentStart: TimeInterval?

  func start(passName: String) {
    guard currentPass == nil, currentStart == nil else {
      fatalError("cannot begin measuring while measuring another pass")
    }
    currentPass = passName
    currentStart = CFAbsoluteTimeGetCurrent()
  }

  func end(passName: String) {
    guard let start = currentStart else {
      fatalError("cannot end timer that has not begun")
    }
    guard currentPass == passName else {
      fatalError("cannot end timer for \(currentPass!) with pass \(passName)")
    }
    timings.append((passName, CFAbsoluteTimeGetCurrent() - start))
    currentStart = nil
    currentPass = nil
  }
}
