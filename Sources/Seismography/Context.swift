//
//  Context.swift
//  Seismography
//
//  Created by Robert Widmann on 10/6/18.
//

import Foundation

public final class GIRContext {
  public struct TypeProfile<T: Value & GIRProfile>: Hashable {
    public let value: T

    init(_ value: T) {
      self.value = value
    }

    public func profile(into hasher: inout Hasher) {
      value.profile(into: &hasher)
    }
  }

  var dataTypes: [Int: TypeProfile<DataType>] = [:]
}

public protocol GIRProfile {
  func profile(into hasher: inout Hasher)
}

extension DataType: GIRProfile {
  public func profile(into hasher: inout Hasher) {
    self.name.hash(into: &hasher)
    if let module = self.module {
      Unmanaged.passUnretained(module).toOpaque().hash(into: &hasher)
    }
    self.constructors.count.hash(into: &hasher)
  }
}
