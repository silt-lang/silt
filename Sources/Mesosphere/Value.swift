//
//  Value.swift
//  Mesosphere
//
//  Created by Harlan Haskins on 12/13/17.
//

import Foundation

final class Value {
  enum Tag {
    case empty
    case immutableValueReference(Definition)
    case mutableValueReference(handle: Int, type: TypeBase)
    case pointerReference(Definition)
    case aggregateReference(Definition)
  }

  let tag: Tag
  unowned var builder: IRBuilder

  init(tag: Tag, builder: IRBuilder) {
    self.tag = tag
    self.builder = builder
  }

  var context: Context {
    return builder.context
  }

  func load(dbg: Debug) -> Definition? {
    switch tag {
    case let .immutableValueReference(definition):
      return definition
    case let .mutableValueReference(handle, type):
      return builder.currentContinuation?.getValue(handle: handle,
                                                   type: type, dbg: dbg)
    case let .pointerReference(definition):
      return builder.load(ptr: definition, dbg: dbg)
    case let .aggregateReference(definition):
      return builder.extract(agg: load(dbg), index: definition, dbg: dbg)
    case .empty:
      fatalError("cannot load from empty value")
    }
  }

  func store(_ value: Definition, dbg: Debug) {
    switch tag {
    case let .mutableValueReference(handle, _):
      builder.currentContinuation?.setValue(handle, value)
    case let .pointerReference(definition):
      builder.store(ptr: definition, val: value, dbg: dbg)
    case let .aggregateReference(definition):
      value.store(context.insert(value.load(dbg), definition, value, dbg), dbg)
    default:
      fatalError("cannot store into \(tag) value")
    }
  }

  var isEmpty: Bool {
    if case .empty = tag { return true }
    return false
  }

  var shouldUseLea: Bool {
    guard case let .pointerReference(definition) = tag else { return false }
    guard let type = definition.type as? PointerType else { return false }
    return useLea(type.pointee)
  }
}
