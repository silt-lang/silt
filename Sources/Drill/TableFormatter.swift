/// TableFormatter.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// Represents a column of tabular values, including a title and rows.
struct Column {
  /// The column's title.
  let title: String

  /// the rows in the column.
  var rows = [String]()

  /// Creates an empty column with the provided title.
  init(title: String) {
    self.title = title
  }

  /// The length of the longest line in this column.
  var width: Int {
    var longest = self.title.count
    for row in self.rows where row.count > longest {
      longest = row.count
    }
    return longest
  }
}

/// An object that formats a set of columns to an output stream as an ASCII
/// table.
enum TableFormatter {
  /// Writes the provided columns as an ASCII table to the provided output
  /// stream. It takes into account the lengths of the columns and ensures a
  /// perfectly-formatted box.
  /// Example:
  /// ```
  /// ┏━━━━━━━━━━━━━┳━━━━━━━━━┓
  /// ┃ Pass        ┃ Time    ┃
  /// ┣━━━━━━━━━━━━━╋━━━━━━━━━┫
  /// ┃ Lex         ┃ 7.4ms   ┃
  /// ┃ Shine       ┃ 1.1ms   ┃
  /// ┃ Parse       ┃ 3ms     ┃
  /// ┃ Dump Parsed ┃ 136.8ms ┃
  /// ┗━━━━━━━━━━━━━┻━━━━━━━━━┛
  /// ```
  static func write<StreamType: TextOutputStream>(
    columns: [Column], to stream: inout StreamType) {
    let widths = columns.map { $0.width }
    stream.write("┏")
    for (idx, width) in widths.enumerated() {
      stream.write(String(repeating: "━", count: width + 2))
      if idx == widths.endIndex - 1 {
        stream.write("┓\n")
      } else {
        stream.write("┳")
      }
    }
    for (column, width) in zip(columns, widths) {
      stream.write("┃ \(column.title.padded(to: width)) ")
    }
    stream.write("┃\n")
    for (index, width) in widths.enumerated() {
      let separator = index == widths.startIndex ? "┣" : "╋"
      stream.write(separator)
      stream.write(String(repeating: "━", count: width + 2))
    }
    stream.write("┫\n")
    for row in 0..<columns[0].rows.count {
      for (column, width) in zip(columns, widths) {
        stream.write("┃ \(column.rows[row].padded(to: width)) ")
      }
      stream.write("┃\n")
    }
    stream.write("┗")
    for (idx, width) in widths.enumerated() {
      stream.write(String(repeating: "━", count: width + 2))
      stream.write(idx == widths.endIndex - 1 ? "┛\n" : "┻")
    }
  }
}

extension String {
  /// Right-pads the given string to the provided length, optionally accepting
  /// a different padding string.
  func padded(to length: Int, with padding: String = " ") -> String {
    let padded = String(repeating: padding, count: length - count)
    return self + padded
  }
}
