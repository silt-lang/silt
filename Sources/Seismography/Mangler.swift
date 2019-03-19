/// Mangler.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

/// A type that can be used to mangle source entities.
public protocol Mangler {
  /// Creates a new mangler.
  init()

  /// Begins a new mangling, aborting any manglings that may be in progress.
  mutating func beginMangling()
  /// Appends a raw string to the current mangling.
  mutating func append(_ : String)
  /// Mangle a string as an identifier.
  mutating func mangleIdentifier(_ : String)
  /// Finalizes the mangler state and returns the mangled name as a `String`.
  mutating func finalize() -> String
}

extension Mangler {
  /// Mangle `value` with this mangler.
  public mutating func mangle<M: ManglingEntity>(_ value: M) -> String {
    self.beginMangling()
    value.mangle(into: &self)
    return self.finalize()
  }
}

public protocol ManglingEntity {
  /// Mangles the entity and any runtime-relevant substructure into the
  /// given mangler.
  func mangle<M: Mangler>(into mangler: inout M)
}

public struct GIRMangler: Mangler {
  /// The storage for the mangled symbol.
  private var buffer: Data = Data()

  /// Substitutions, except identifier substitutions.
  private var substitutions: [String: UInt] = [:]

  /// Identifier substitutions.
  private var identifierSubstitutions: [String: UInt] = [:]

  /// Word substitutions in mangled identifiers.
  private var substitutionWordRanges: [Range<Data.Index>] = []

  public init() {}

  public mutating func beginMangling() {
    self.buffer.removeAll()
    self.buffer.reserveCapacity(128)
    self.substitutions.removeAll()
    self.identifierSubstitutions.removeAll()
    self.substitutionWordRanges.removeAll()
    self.buffer.append(MANGLING_PREFIX, count: MANGLING_PREFIX.count)
  }

  public func finalize() -> String {
    assert(!buffer.isEmpty, "Mangling an empty name")
    guard let result = String(data: self.buffer, encoding: .utf8) else {
      fatalError()
    }

    #if DEBUG
    if result.starts(with: MANGLING_PREFIX) {
      verify(result)
    }
    #endif

    return result
  }

  func verify(_ nameStr: String) {
#if DEBUG
    assert(nameStr.starts(with: MANGLING_PREFIX),
           "mangled name must start with '\(MANGLING_PREFIX)'")

    guard let root = Demangler.demangleSymbol(nameStr) else {
      fatalError("Can't demangle: \(nameStr)")
    }

    var remangler = Remangler()
    root.mangle(into: &remangler)
    let remangled = remangler.finalize()
    guard remangled == nameStr else {
      fatalError("""
      Remangling failed:
        - Started with mangling: \(nameStr)
        - Which remangled to: \(remangled)
      """)
    }
#endif
  }

  public mutating func append(_ str: String) {
    self.buffer.append(str, count: str.count)
  }

  public mutating func mangleIdentifier(_ orig: String) {
    return mangleIdentifierImpl(orig,
                                  &self.buffer, &self.substitutionWordRanges)
  }
}

private func needsPunycodeEncoding(_ ident: Data) -> Bool {
  for byte in ident {
    guard byte.isValidSymbol else {
      return true
    }
  }
  return false
}

internal func mangleIdentifierImpl(
  _ orig: String, _ buffer: inout Data,
  _ substitutionWordRanges: inout [Range<Data.Index>]
) {
  let ident = orig.data(using: .utf8)!
  guard !needsPunycodeEncoding(ident) else {
    // If the identifier contains non-ASCII character, we mangle
    // with an initial '00' and Punycode the identifier string.
    let punycoder = Punycode()
    guard let punycodeBuf = punycoder.encode(utf8String: orig.utf8) else {
      return
    }
    buffer.append("00", count: "00".count)
    buffer.append("\(punycodeBuf.count)",
                       count: "\(punycodeBuf.count)".count)
    let firstChar = punycodeBuf.utf8.first!
    if firstChar.isDigit || firstChar == ManglingScalars.DOLLARSIGN {
      buffer.append(ManglingScalars.DOLLARSIGN)
    }
    buffer.append(punycodeBuf, count: punycodeBuf.count)
    return
  }

  // Search for word substitutions and for new words.
  let substWordsInIdent = searchForSubstitutions(ident, buffer,
                                                 &substitutionWordRanges)
  assert(!substWordsInIdent.isEmpty)

  // If we have substitutions, mangle in a '0'.
  if substWordsInIdent.count > 1 {
    buffer.append(ManglingScalars.ZERO)
  }

  // Mangle the sequence of substitutions and intervening strings.
  mangleApplyingSubstitutions(ident, substWordsInIdent,
                              &buffer, &substitutionWordRanges)
}

// FIXME: Remove for 4.2
// swiftlint:disable syntactic_sugar
private func firstIndexOfMatch(
  _ arr: [Range<Data.Index>], _ pred: (Range<Data.Index>) -> Bool
) -> Array<Range<Data.Index>>.Index? {
  for i in arr.startIndex..<arr.endIndex {
    if pred(arr[i]) {
      return i
    }
  }
  return nil
}
// swiftlint:enable syntactic_sugar

private func searchForSubstitutions(
  _ buf: Data, _ buffer: Data,
  _ substitutionWordRanges: inout [Range<Data.Index>]
) -> [Substitution] {
  var result = [Substitution]()
  var wordStartPos: Int?
  for i in buf.startIndex...buf.endIndex {
    let ch = i < buf.endIndex ? buf[i] : ManglingScalars.NUL
    if let startPos = wordStartPos {
      if ManglingScalars.isEndOfWord(ch, buf[buf.index(before: i)]) {
        assert(i > startPos)
        let wordLen = buf.distance(from: startPos, to: i)
        let word = buf.subdata(in: startPos..<startPos + wordLen)

        // Is the word already present in the in-flight mangled string?
        let existingIdx = firstIndexOfMatch(substitutionWordRanges) { range in
          return word == buffer[range]
        }

        if let idx = existingIdx {
          assert(idx < MAXIMUM_WORDS_CAPACITY,
                 "Mangled name exceeds maximum number of substitutions")
          result.append(.init(position: startPos, index: idx))
        } else if wordLen >= 2 {
          // Note: at this time the word's start position is relative to the
          // begin of the identifier. We must update it afterwards so that it
          // is relative to the begin of the whole mangled Buffer.
          addSubstitutionIfPossible(startPos..<startPos + wordLen,
                                    &substitutionWordRanges)
        }
        wordStartPos = nil
      }
    }

    guard wordStartPos == nil && ch.isStartOfWord else {
      continue
    }

    // This position is the begin of a word.
    wordStartPos = i
  }

  // Add a dummy-word at the end of the list.
  result.append(.init(position: buf.endIndex))

  return result
}

private func mangleApplyingSubstitutions(
  _ ident: Data, _ substitutions: [Substitution], _ buffer: inout Data,
  _ substitutionWordRanges: inout [Range<Data.Index>]
) {
  var lastSub = substitutionWordRanges.count
  var lastPos = ident.startIndex
  for (i, replacement) in substitutions.enumerated() {
    if lastPos < replacement.position {
      // Mangle the sub-string up to the next word substitution (or to the end
      // of the identifier - that's why we added the dummy-word).
      // The first thing: we add the encoded sub-string length.
      let dist = ident.distance(from: lastPos, to: replacement.position)
      buffer.append("\(dist)", count: "\(dist)".count)
      assert(!ident[lastPos].isDigit,
             "first char of sub-string to mangle may not be a digit")
      repeat {
        // Update the start position of new added words, so that they refer to
        // the begin of the whole mangled Buffer.
        if lastSub < substitutionWordRanges.count {
          let oldSub = substitutionWordRanges[lastSub]
          if oldSub.lowerBound == lastPos {
            updateStartOfNewSubstitution(&substitutionWordRanges,
                                         &lastSub, buffer.count)
          }
        }
        // Append the start of the sub-string.
        buffer.append(ident[lastPos])
        ident.formIndex(after: &lastPos)
      } while lastPos < replacement.position
    }

    // Is it a "real" word substitution (and not the dummy-word)?
    guard let replIndex = replacement.index else {
      continue
    }

    assert(replIndex <= lastSub)
    ident.formIndex(&lastPos, offsetBy: substitutionWordRanges[replIndex].count)
    if i < substitutions.count - 2 {
      buffer.append(UInt8(replIndex) + ManglingScalars.LOWERCASE_A)
    } else {
      // The last word substitution is a capital letter.
      buffer.append(UInt8(replIndex) + ManglingScalars.UPPERCASE_A)
      if lastPos == ident.endIndex {
        buffer.append(ManglingScalars.ZERO)
      }
    }
  }
}

private func addSubstitutionIfPossible(
  _ range: Range<Data.Index>,
  _ substitutionWordRanges: inout [Range<Data.Index>]
) {
  if substitutionWordRanges.count < MAXIMUM_WORDS_CAPACITY {
    substitutionWordRanges.append(range)
  }
}

private func updateStartOfNewSubstitution(
  _ substitutionWordRanges: inout [Range<Data.Index>],
  _ pos: inout Int, _ bufCount: Int
) {
  precondition(pos < substitutionWordRanges.count)

  let oldSub = substitutionWordRanges[pos]
  substitutionWordRanges[pos] = bufCount..<bufCount + oldSub.count
  pos += 1
}


struct Identifier: ManglingEntity {
  private let str: String
  init(_ str: String) {
    self.str = str
  }

  public func mangle<M: Mangler>(into mangler: inout M) {
    mangler.mangleIdentifier(self.str)
  }
}

extension String: ManglingEntity {
  public func mangle<M: Mangler>(into mangler: inout M) {
    mangler.append(self)
  }
}

extension GIRModule: ManglingEntity {
  public func mangle<M: Mangler>(into mangler: inout M) {
    Identifier(self.name).mangle(into: &mangler)
  }
}

/// Helper struct which represents a word substitution.
private struct Substitution {
  /// The position in the identifier where the word is substituted.
  let position: Data.Index

  /// The index into the mangler's Words array (-1 if invalid).
  let index: Int?

  init(position: Data.Index, index: Int? = nil) {
    self.position = position
    self.index = index
  }
}
