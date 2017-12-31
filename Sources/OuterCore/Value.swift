/// Value.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

public class Value {
  private(set) var operands: [Value]

  init(operands: [Value] = []) {
    self.operands = operands
  }
}

public class Parameter: Value {
}
