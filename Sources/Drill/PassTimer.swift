/// PassTimer.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A class that keeps track of the elapsed time of a sequence of compiler
/// passes. It also includes behavior to dump a table of values representing the
/// times of all passes run in the compile session.
class PassTimer {
  /// The order of passes executed.
  private var passOrder = [String]()

  /// The time taken for each pass.
  private var timings = [String: TimeInterval]()


  /// Measures the time taken for the underlying block, and returns whatever
  /// value the underlying block returns.
  ///
  /// - Parameters:
  ///   - pass: The name of the pass being executed.
  ///   - actions: A function corresponding to the pass's actions.
  /// - Returns: The return value of the pass.
  func measure<Out>(pass: String, actions: () -> Out) -> Out {
    // FIXME: Date() is wasteful here...
    let start = Date()
    defer {
      passOrder.append(pass)
      timings[pass, default: 0] += Date().timeIntervalSince(start)
    }
    return actions()
  }


  /// Dumps a formatted table of timings to the provided stream.
  ///
  /// - Parameter target: The stream to write the table to.
  func dump<Target: TextOutputStream>(to target: inout Target) {
    var columns = [Column(title: "Pass"), Column(title: "Time")]
    for pass in passOrder {
      columns[0].rows.append(pass)
      if let time = timings[pass] {
        columns[1].rows.append(time.formatted)
      } else {
        columns[1].rows.append("N/A")
      }
    }
    TableFormatter.write(columns: columns, to: &target)
  }
}

extension TimeInterval {
  /// A NumberFormatter used for printing formatted time intervals.
  private static let intervalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 1
    return formatter
  }()

  /// Formats a time interval at second, millisecond, microsecond, and
  /// nanosecond boundaries.
  ///
  /// - Parameter interval: The interval you're formatting.
  /// - Returns: A stringified version of the time interval, including the most
  ///            appropriate unit.
  public var formatted: String {
    var interval = self
    let unit: String
    if interval > 1.0 {
      unit = "s"
    } else if interval > 0.001 {
      unit = "ms"
      interval *= 1_000
    } else if interval > 0.000_001 {
      unit = "µs"
      interval *= 1_000_000
    } else {
      unit = "ns"
      interval *= 1_000_000_000
    }
    let nsNumber = NSNumber(value: interval)
    return TimeInterval.intervalFormatter.string(from: nsNumber)! + unit
  }
}
