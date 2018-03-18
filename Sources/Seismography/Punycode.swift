/// Punycode.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

// MARK: RFC 3492

// MARK: 5: Parameter values for Punycode

private let base        = 36
private let tmin        = 1
private let tmax        = 26
private let skew        = 38
private let damp        = 700
private let initialBias = 72
private let initialN    = 128 as Unicode.UTF32.CodeUnit

private func isValidUnicodeScalar(_ unit: Unicode.UTF32.CodeUnit) -> Bool {
  return (unit < 0xD880) || (unit >= 0xE000 && unit <= 0x1FFFFF)
}

// MARK: 6.1: Bias adaptation function

private func adapt(
  _ startDelta: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
  var delta = startDelta
  if firstTime {
    delta /= damp
  } else {
    delta /= 2
  }
  delta += delta / numPoints
  var k = 0
  while delta > ((base - tmin) * tmax) / 2 {
    delta /= base - tmin
    k += base
  }
  return k + (((base - tmin + 1) * delta) / (delta + skew))
}

public final class Punycode {
  public let delimiter: String
  private let delimiterCodeUnit: UTF32.CodeUnit
  private let encodeTable: [Int: Character]
  private let decodeTable: [UTF32.CodeUnit: Int]

  public init() {
    self.delimiter = "_"
    guard let delimUnitRes = UTF32.encode("_") else {
      fatalError("Unable to UTF32 encode delimiter: '_'")
    }
    self.delimiterCodeUnit = delimUnitRes[0]

    let table = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ"
    let encodeTableSeq = zip(0..<table.count, table)
    self.encodeTable = [Int: Character](encodeTableSeq,
                                        uniquingKeysWith: { $1 })
    // swiftlint:disable closure_parameter_position
    let backMapping = table.unicodeScalars.map {
      (_ s: Unicode.Scalar) -> UTF32.CodeUnit in

      guard let codedUnit = UTF32.encode(s) else {
        fatalError("Unable to UTF32 encode scalar from table: '\(s)'")
      }
      return codedUnit[0]
    }
    let decodeTableSeq = zip(backMapping,
                             0..<table.count)
    self.decodeTable = [UTF32.CodeUnit: Int](decodeTableSeq,
                                             uniquingKeysWith: { $1 })
  }

  // MARK: 6.3: Decoding procedure

  /// Decode a UTF-8 encoded string with Punycode.
  ///
  /// On failure, this function returns `nil`.
  public func decode(utf8String: String.UTF8View) -> String? {
    var codeUnits: [UTF32.CodeUnit] = []
    codeUnits.reserveCapacity(utf8String.count)
    let sink = { codeUnits.append($0) }
    guard !transcode(utf8String.makeIterator(), from: UTF8.self, to: UTF32.self,
                    stoppingOnError: true, into: sink) else {
      return nil
    }
    var sinkChars: [UTF32.CodeUnit] = []
    sinkChars.reserveCapacity(utf8String.count)
    guard self.decode(utf32String: codeUnits, &sinkChars) else {
      fatalError()
    }

    var scalars: [Unicode.Scalar] = []
    var utf32Decoder = UTF32()
    var codeUnitIterator = sinkChars.makeIterator()
    Decode: while true {
      switch utf32Decoder.decode(&codeUnitIterator) {
      case .scalarValue(let v): scalars.append(v)
      case .emptyInput: break Decode
      case .error:
        fatalError("Decoding error on input \(utf8String)")
      }
    }
    return String(String.UnicodeScalarView(scalars))
  }

  private func decode(
    utf32String: [UTF32.CodeUnit], _ sink: inout [UTF32.CodeUnit]) -> Bool {
    var n = initialN
    var i = 0
    var bias = initialBias

    var pos = 0
    if let dpos = utf32String.index(of: delimiterCodeUnit) {
      for c in utf32String[0..<dpos] {
        guard c <= 0x7f else {
          return true
        }
        sink.append(c)
      }
      pos += dpos + 1
    }
    while pos < utf32String.count {
      let oldi = i
      var w = 1
      var k = base
      while true {
        defer { k += base }
        let digit = self.decodeTable[utf32String[pos]]!
        pos += 1
        guard digit >= 0 else {
          return true
        }
        i += digit * w
        let t = max(min(k - bias, tmax), tmin)
        guard digit >= t else {
          break
        }
        w = w * (base - t)
      }
      bias = adapt(i - oldi, sink.count + 1, oldi == 0)
      n = UTF32.CodeUnit(Int(n) + i / (sink.count + 1))
      i = i % (sink.count + 1)
      guard n >= 0x80 else {
        return true
      }
      sink.insert(n, at: i)
      i += 1
    }
    return true
  }

  /// Encode a UTF-8 encoded string with Punycode.
  ///
  /// On failure, this function returns `nil`.
  public func encode(utf8String: String.UTF8View) -> String? {
    var codeUnits: [UTF32.CodeUnit] = []
    codeUnits.reserveCapacity(utf8String.count)
    let sink = { codeUnits.append($0) }
    guard !transcode(utf8String.makeIterator(), from: UTF8.self, to: UTF32.self,
                    stoppingOnError: true, into: sink) else {
      return nil
    }
    var sinkStr: String = ""
    guard self.encode(utf32String: codeUnits, &sinkStr) else {
      fatalError()
    }
    return sinkStr
  }

  // MARK: 6.3: Encoding procedure

  private func encode<Sink: TextOutputStream>(
    utf32String: [UTF32.CodeUnit], _ sink: inout Sink) -> Bool {
    var n = initialN
    var delta = 0
    var bias = initialBias

    // Count the number of basic code points in the input and validate.
    var h = 0 as Unicode.UTF32.CodeUnit
    for c in utf32String {
      if c < 0x80 {
        h += 1
        UTF32.decode(CollectionOfOne(c)).write(to: &sink)
      }

      // if the input contains a non-basic code point < n then fail
      guard isValidUnicodeScalar(c) else {
        return false
      }
    }

    // let h = b = the number of basic code pointsin the input
    var b = h
    // after copying them to the ouput in order, write the delimited if b > 0
    if b > 0 {
      delimiter.write(to: &sink)
    }
    while h < utf32String.count {
      // let m = the minimum code point >= n in the input
      var m = 0x10FFFF as Unicode.UTF32.CodeUnit
      for codePoint in utf32String {
        if codePoint >= n && codePoint < m {
          m = codePoint
        }
      }

      delta += Int(m - n) * Int(h + 1)
      n = m

      // For each code point 'c' in the input (in order):
      for c in utf32String {
        if c < n {
          delta += 1
        } else if c == n {
          var q = delta
          // for k = base to infinity in steps of base:
          var k = base
          while true {
            defer { k += base }
            let t = max(min(k - bias, tmax), tmin)

            guard q >= t else {
              break
            }
            // output the code point for digit `t + ((q - t) % (base - t))`.\
            self.encodeTable[t + ((q - t) % (base - t))]!.write(to: &sink)
            q = (q - t) / (base - t)
          }
          // output the code point for digit q
          self.encodeTable[q]!.write(to: &sink)
          bias = adapt(delta, Int(h + 1), h == b)
          // let delta = 0
          delta = 0
          // increment h
          h += 1
        }
      }
      // increment delta and n
      delta += 1
      n += 1
    }
    return true
  }
}
