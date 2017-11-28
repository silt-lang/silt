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
    // FIXME: Date() is wasteful here...
    let start = Date()
    defer {
      timings.append((pass, Date().timeIntervalSince(start)))
    }
    return actions()
  }

  func dump<Target: TextOutputStream>(to target: inout Target) {
    var columns = [Column(title: "Pass"), Column(title: "Time")]
    for (pass, time) in timings {
      columns[0].rows.append(pass)
      columns[1].rows.append(format(time: time))
    }
    TableFormatter(columns: columns).write(to: &target)
  }
}

private func format(time: Double) -> String {
  var time = time
  let unit: String
  let formatter = NumberFormatter()
  formatter.maximumFractionDigits = 3
  if time > 1.0 {
    unit = "s"
  } else if time > 0.001 {
    unit = "ms"
    time *= 1_000
  } else if time > 0.000_001 {
    unit = "µs"
    time *= 1_000_000
  } else {
    unit = "ns"
    time *= 1_000_000_000
  }
  return formatter.string(from: NSNumber(value: time))! + unit
}
