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

  /// The offset of this location from the beginning of the file.
  public var offset: Int
}

/// Represents a range of locations in source code.
public struct SourceRange {
  /// The start of the source range.
  public let start: SourceLocation

  /// The end of the source range.
  public let end: SourceLocation
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
