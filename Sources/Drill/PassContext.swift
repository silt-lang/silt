/// PassContext.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

/// A class that's passed to invocations of each pass. It contains a timer
/// and diagnostic engine that each pass can make use of.
final class PassContext {
  /// A timer that records the running time of each individual pass.
  let timer = PassTimer()

  /// The diagnostic engine which passes should use to diagnose errors and
  /// warnings.
  let engine = DiagnosticEngine()
}
