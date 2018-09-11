/// Mangling.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

public let MANGLING_PREFIX = "_S"
internal let MAXIMUM_WORDS_CAPACITY = 26

internal enum ManglingScalars {
  static let NUL = UInt8(ascii: "\0")

  static let LOWERCASE_A = UInt8(ascii: "a")
  static let UPPERCASE_A = UInt8(ascii: "A")

  static let UPPERCASE_B = UInt8(ascii: "B")

  static let UPPERCASE_D = UInt8(ascii: "D")

  static let UPPERCASE_F = UInt8(ascii: "F")
  static let LOWERCASE_F = UInt8(ascii: "f")

  static let LOWERCASE_T = UInt8(ascii: "t")

  static let LOWERCASE_Y = UInt8(ascii: "y")


  static let LOWERCASE_Z = UInt8(ascii: "z")
  static let UPPERCASE_Z = UInt8(ascii: "Z")

  static let AMPERSAND = UInt8(ascii: "&")
  static let UNDERSCORE = UInt8(ascii: "_")
  static let DOLLARSIGN = UInt8(ascii: "$")

  static let ZERO = UInt8(ascii: "0")
  static let NINE = UInt8(ascii: "9")

  static func isEndOfWord(_ cur: UInt8, _ prev: UInt8) -> Bool {
    if cur == DOLLARSIGN || cur == NUL {
      return true
    }

    if !prev.isUpperLetter && cur.isUpperLetter {
      return true
    }

    return false
  }
}

extension UInt8 {
  var isLowerLetter: Bool {
    return self >= ManglingScalars.LOWERCASE_A
        && self <= ManglingScalars.LOWERCASE_Z
  }

  var isUpperLetter: Bool {
    return self >= ManglingScalars.UPPERCASE_A
        && self <= ManglingScalars.UPPERCASE_Z
  }

  var isDigit: Bool {
    return self >= ManglingScalars.ZERO && self <= ManglingScalars.NINE
  }

  var isLetter: Bool {
    return self.isLowerLetter || self.isUpperLetter
  }

  var isValidSymbol: Bool {
    return self < 0x80
  }

  var isStartOfWord: Bool {
    return !(self.isDigit || self == ManglingScalars.DOLLARSIGN
                          || self == ManglingScalars.NUL)
  }
}
