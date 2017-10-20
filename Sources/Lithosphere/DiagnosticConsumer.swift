/// DiagnosticConsumer.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Foundation

/// A DiagnosticConsumer receives updates as the DiagnosticEngine pushes
/// diagnostics into its internal storage. It's responsible for converting
/// the content of the diagnostics into a different form for serialization,
/// textual output, and whatever else it wants.
public protocol DiagnosticConsumer {
  /// Called when the diagnostic engine pops any diagnostic. Use this as
  /// the opportunity to update your internal storage or output the contents
  /// of the diagnostic to a file.
  ///
  /// - Parameter diagnostic: The diagnostic that was just added to the engine.
  func handle(_ diagnostic: Diagnostic)

  /// Perform whatever cleanup is necessary to commit whatever your consumer
  /// needs to make permanent. This usually means flushing and closing files.
  func finalize()
}
