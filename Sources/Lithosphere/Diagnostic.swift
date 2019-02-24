/// Diagnostic.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Foundation

/// Represents a diagnostic that expresses a failure or warning condition found
/// during compilation.
public struct Diagnostic {
  /// Represents location information associated with diagnostics.
  public enum Location {
    case unknown
    case location(SourceLocation)
    case node(Syntax)
  }

  /// A Note is a piece of extra information attached to a diagnostic. Notes are
  /// useful for suggestions when the fix for an issue is not immediately
  /// obvious. By convention, silt will attach one or more notes to a diagnostic
  /// when it is not certain about the exact fix for the issue.
  public struct Note {
    /// The message attached to the Note.
    public let message: Message

    /// A set of nodes that will be 'highlighted', that may provide more context
    /// to a particular note.
    public let highlights: [Syntax]

    /// The location associated with this diagnostic note.
    public let location: Location

    public func sourceLocation(
      converter: SourceLocationConverter
    ) -> SourceLocation? {
      switch self.location {
      case .unknown:
        return nil
      case let .location(loc):
        return loc
      case let .node(node):
        return node.startLocation(converter: converter)
      }
    }
  }

  /// Represents a diagnostic message. Clients should extend this struct with
  /// static constants or functions to enable leading-dot-style references to
  /// diagnostic messages.
  public struct Message: Error {
    /// The severity of the message, expressing how the compiler treats it.
    public enum Severity: String {
      /// The message is a warning that will not prevent compilation but that
      /// the silt compiler feels might signal code that does not behave the way
      /// the programmer expected.
      case warning

      /// The message is an error that violates a rule for the silt language.
      /// This error might not necessarily prevent further processing of the
      /// source file after it is emitted, but will ultimately prevent silt from
      /// producing an executable.
      case error

      /// The mesage is a note that will be attached to a diagnostic and provide
      /// more context for a failure to assist triage, or give a suggestion for
      /// how to fix the program.
      case note
    }
    public let severity: Severity
    public let text: String

    public init(_ severity: Severity, _ text: String) {
      self.severity = severity
      self.text = text
    }
  }

  /// The textual message that the diagnostic intends to print.
  public let message: Message

  /// The location this diagnostic is associated with.
  public let location: Location

  /// A set of nodes that will be 'highlighted', that may provide more context
  /// to a particular diagnostic.
  public let highlights: [Syntax]

  /// A set of notes on this diagnostic.
  public let notes: [Note]

  public func sourceLocation(
    converter: SourceLocationConverter
  ) -> SourceLocation? {
    switch self.location {
    case .unknown:
      return nil
    case let .location(loc):
      return loc
    case let .node(node):
      return node.startLocation(converter: converter)
    }
  }

  /// A diagnostic builder is an object that lets you incrementally add
  /// highlights and notes to a diagnostic. It's only accessible through
  /// Diagnostic's Builder initializer, which takes the static fields up front
  /// and provides methods to add notes and highlights incrementally.
  public struct Builder {
    /// The notes that will be attached to the resulting diagnostic.
    private var notes = [Note]()

    /// The highlights that will be attached to the resulting diagnostic.
    private var highlights = [Syntax]()

    /// Adds a highlighted Syntax node to this builder.
    /// - parameter note: The highlight to add.
    public mutating func highlight(_ nodes: Syntax...) {
      highlight(nodes)
    }

    /// Adds a highlighted Syntax node to this builder.
    /// - parameter note: The highlight to add.
    public mutating func highlight(_ nodes: [Syntax]) {
      highlights.append(contentsOf: nodes)
    }

    /// Adds the provided note to this builder.
    /// - parameter note: The note to add.
    public mutating func note(_ note: Note) {
      notes.append(note)
    }

    /// Constructs a note from the constituent parts and adds it to this
    /// builder.
    ///
    /// - Parameters:
    ///   - message: The message in the note.
    ///   - node: The node to attach the new note to.
    ///   - highlights: The nodes to highlight for this node.
    public mutating func note(_ message: Message,
                              location: Location = .unknown,
                              highlights: [Syntax] = []) {
      precondition(message.severity == .note,
                   "cannot create a note with severity \(message.severity)")
      note(Note(message: message, highlights: highlights, location: location))
    }

    /// Constructs a note from the constituent parts and adds it to this
    /// builder.
    ///
    /// - Parameters:
    ///   - message: The message in the note.
    ///   - node: The node to attach the new note to.
    ///   - highlights: The nodes to highlight for this node.
    public mutating func note(_ message: Message,
                              node: Syntax,
                              highlights: [Syntax] = []) {
      self.note(message, location: .node(node), highlights: highlights)
    }

    /// Builds a Diagnostic from the current set of values in the builder.
    /// This can only be called by the Diagnostic builder initializer.
    /// - parameters:
    ///   - message: The diagnostic's message.
    ///   - node: The node to attach the diagnostic to.
    ///   - severity: The severity of the resulting diagnostic.
    /// - returns: The diagnostic made by combining the parameters with the
    ///            current internal state of the builder.
    internal func build(
      message: Message,
      location: Location = .unknown
    ) -> Diagnostic {
      return Diagnostic(message: message,
                        location: location,
                        highlights: highlights,
                        notes: notes)
    }
  }

  /// Creates a Diagnostic with a given severity and message, attached to a
  /// given node, highlighting the given nodes, with the given notes.
  ///
  /// - Parameters:
  ///   - severity: The severity of the diagnostic.
  ///   - message: The message describing the diagnostic.
  ///   - node: The node to which this diagnostic is attached. Defaults to
  ///           `nil`.
  ///   - highlights: The set of nodes that are highlighted in this diagnostic.
  ///   - notes: The set of notes applied to this diagnostic.
  /// - Returns: A Diagnostic that contains the provided fields.
  public init(message: Message,
              location: Location, highlights: [Syntax], notes: [Note]) {
    precondition(message.severity != .note,
                 "cannot create a diagnostic with note severity")
    self.message = message
    self.location = location
    self.highlights = highlights
    self.notes = notes
  }

  /// Represents a function that will take a mutable Diagnostic.Builder and
  /// make mutating calls into it to incrementally build up a diagnostic.
  public typealias BuildActions = (inout Builder) -> Void

  /// Creates a Diagnostic with a given severity and message, attached to a
  /// given node, highlighting the given nodes, with the given notes.
  ///
  /// - Parameters:
  ///   - severity: The severity of the diagnostic.
  ///   - message: The message describing the diagnostic.
  ///   - node: The node to which this diagnostic is attached. Defaults to
  ///           `nil`.
  ///   - actions: A closure that will attach highlights and notes to a
  ///              diagnostic builder.
  /// - Returns: A Diagnostic that contains the provided fields.
  internal init(message: Message, location: Location, actions: BuildActions?) {
    var builder = Builder()
    actions?(&builder)
    self = builder.build(message: message, location: location)
  }
}

extension Diagnostic.Message {
  /// Returns a string of the appropriate pluralization given a count.
  public static func pluralize(
    singular: String, plural: String, _ count: Int
  ) -> String {
    return (count == 1) ? singular : plural
  }
}
