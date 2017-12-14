//
//  Debug.swift
//  Mesosphere
//
//  Created by Harlan Haskins on 12/13/17.
//

import Lithosphere

public struct Debug {
  let range: SourceRange?
  let name: String

  init(range: SourceRange? = nil, name: String = "") {
    self.range = range
    self.name = name
  }
}

func +(lhs: Debug, rhs: Debug) -> Debug {
  var start = lhs.range?.start
  var end = rhs.range?.end
  if lhs.range == nil {
    start = rhs.range?.start
  }
  if rhs.range == nil {
    end = lhs.range?.end
  }
  var range: SourceRange? = nil
  if let finalStart = start, let finalEnd = end {
    range = SourceRange(start: finalStart, end: finalEnd)
  }
  return Debug(range: range,
               name: "\(lhs.name).\(rhs.name)")
}

func +(lhs: Debug, rhs: String) -> Debug {
  return Debug(range: lhs.range,
               name: "\(lhs.name)\(rhs)")
}

