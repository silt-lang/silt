/// String+Helpers.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

private let commonSwiftKeywords = ["if", "else", "for", "operator", "case"]
extension String {
  var uppercaseFirstLetter: String {
    var copy = self
    copy.replaceSubrange(startIndex..<index(after: startIndex),
                         with: String(self[startIndex]).uppercased())
    return copy
  }

  var asStandaloneIdentifier: String {
    var copy = lowercaseFirstLetter
    if commonSwiftKeywords.contains(copy) {
      copy = "`\(copy)`"
    }
    return copy
  }

  var lowercaseFirstLetter: String {
    var copy = self
    copy.replaceSubrange(startIndex..<index(after: startIndex),
                         with: String(self[startIndex]).lowercased())
    return copy
  }
}
