/// Type.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Mantle

public class ProductType: TypeBase {
  let name: String
  init(in context: Context, name: String, size: Int) {
    self.name = name
    super.init(in: context,
               typeOperands: [TypeBase](repeating: BottomType(in: context),
                                        count: size))
  }
}

public class SumType: TypeBase {
  init(in context: Context, elements: [TypeBase]) {
    precondition(elements.adjacentFind(==) == nil)
    super.init(in: context, typeOperands: elements)
  }
}

public class FunctionType: TypeBase {
  init(in context: Context, elements ops: [TypeBase] = []) {
    super.init(in: context, typeOperands: ops)
    self.order += 1
  }
}

class BottomType: TypeBase {
  init(in context: Context) {
    super.init(in: context, typeOperands: [])
  }
}

public class TypeBase : Hashable {
  private static var idPool: Int = 0
  private var id: Int

  var order: Int = 0

  var monomorphic = true

  let context: Context
  var operands: [TypeBase]

  init(in context: Context, typeOperands: [TypeBase]) {
    defer { TypeBase.idPool += 1 }
    self.id = TypeBase.idPool

    self.context = context

    self.operands = []
    self.operands.reserveCapacity(typeOperands.count)
    for typeOp in typeOperands {
      self.operands.append(typeOp)
      self.order = max(self.order, typeOp.order)
      self.monomorphic = self.monomorphic && typeOp.monomorphic
    }
  }

  public var hashValue: Int {
    var hash = self.order
    if self.monomorphic { hash += 1 }
    for op in self.operands {
      hash ^= op.hashValue
    }
    return hash
  }

  public static func == (lhs: TypeBase, rhs: TypeBase) -> Bool {
    var result = lhs.operands.count == rhs.operands.count
              && lhs.monomorphic == rhs.monomorphic

    if result {
      var i = 0
      while result && i < lhs.operands.count {
        defer { i += 1 }
        result = result && lhs.operands[i] == rhs.operands[i]
      }
    }

    return result
  }

  func set(_ i : Int, type: TypeBase) {
    self.operands[i] = type
    self.order = max(self.order, type.order)
    self.monomorphic = self.monomorphic && type.monomorphic
  }
}

