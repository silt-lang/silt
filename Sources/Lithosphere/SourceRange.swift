/// SourceRange.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

/// Represents a location in source code.
public struct SourceLocation {
  /// The line on which the code lies.
  public var line: Int

  /// The column where the code begins.
  public var column: Int

  /// The file in which the code lies.
  public let file: String

  /// The character offset of this location from the beginning of the file.
  public var offset: Int

  /// Creates a SourceLocation pointing to a specific location in a file.
  ///
  /// - Parameters:
  ///   - line: The line on which the code lies.
  ///   - column: The column where the code begins.
  ///   - file: The file in which the code lies.
  ///   - offset: The character offset of this location from the beginning of
  ///             the file.
  public init(line: Int, column: Int, file: String, offset: Int) {
    self.line = line
    self.column = column
    self.file = file
    self.offset = offset
  }
}

/// Represents a range of locations in source code.
public struct SourceRange {
  /// The start of the source range.
  public let start: SourceLocation

  /// The end of the source range.
  public let end: SourceLocation

  /// Creates a SourceRange with the given bounds in the provided file.
  ///
  /// - Parameters:
  ///   - start: The starting source location of this range.
  ///   - end: The end source location of this range.
  /// - Precondition:
  ///   - `start` and `end` exist in the same file.
  public init(start: SourceLocation, end: SourceLocation) {
    precondition(start.file == end.file,
                 "Both locations in a range must be in the same file.")
    self.start = start
    self.end = end
  }
}

/// The presence of a particular bit of syntax.
public enum SourcePresence {
  /// The syntax is present in the source code
  case present

  /// The syntax is implicit in the source code, but not associated with a line
  /// in a source file.
  case implicit

  /// The syntax is not linked to source code and does not appear in the tree.
  case missing
}
