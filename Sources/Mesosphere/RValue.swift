/// RValue.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle
import Seismography

extension GIRGenFunction {
  func emitRValue(
    _ parent: Continuation, _ body: Term<TT>
  ) -> (Continuation, ManagedValue) {
    switch body {
    case let .apply(head, args):
      switch head {
      case let .definition(defName):
        let constant = DeclRef(defName.key.string, .function)
        let callee = self.B.module.lookupContinuation(constant)!
        let calleeRef = self.B.createFunctionRef(callee)
        let applyDest = self.B.buildContinuation(
                          name: self.f.name + "apply#\(defName.key.string)")
        let applyDestRef = self.B.createFunctionRef(applyDest)
        let param = applyDest.appendParameter(type: callee.returnValueType)
        var lastParent = parent
        var argVals = [Value]()
        argVals.reserveCapacity(args.count)
        for arg in args {
          let (newParent, value) = self.emitElimAsRValue(lastParent, arg)
          argVals.append(value.forward(self))
          lastParent = newParent
        }
        argVals.append(applyDestRef)
        _ = self.B.createApply(lastParent, calleeRef, argVals)
        return (applyDest, ManagedValue.unmanaged(param))
      case let .meta(mv):
        guard let bind = self.tc.signature.lookupMetaBinding(mv) else {
          fatalError()
        }
        return self.emitRValue(parent, bind.body)
      case let .variable(v):
        guard let varLocVal = self.varLocs[v.name] else {
          fatalError()
        }
        if varLocVal.type is BoxType {
          let lowering = self.lowerType(varLocVal.type)
          if !lowering.addressOnly {
            let loadVal = self.B.createLoadBox(varLocVal)
            return (parent, ManagedValue.unmanaged(loadVal))
          } else {
            let projected = self.B.createProjectBox(varLocVal,
                                                    type: lowering.type)
            return (parent, ManagedValue.unmanaged(projected))
          }
        }
        return (parent, ManagedValue.unmanaged(varLocVal))
      }
    case let .constructor(tag, args):
      var lastParent = parent
      var argVals = [Value]()
      let payloadType = self.getPayloadTypeOfConstructor(tag)
      assert(payloadType.count == args.count)
      argVals.reserveCapacity(args.count)
      for (ty, arg) in zip(payloadType, args) {
        let (newParent, originalValue) = self.emitRValue(lastParent, arg)
        if ty is BoxType {
          let underlyingTyLowering = self.lowerType(ty)
          if underlyingTyLowering.addressOnly {
            let box = B.createAllocBox(underlyingTyLowering.type)
            let addr = B.createProjectBox(box, type: underlyingTyLowering.type)
            let storedBox = B.createCopyAddress(
              originalValue.forward(self), to: addr)
            let finalValue = self.pairValueWithCleanup(storedBox)
            argVals.append(finalValue.forward(self))
          } else {
            let box = B.createAllocBox(underlyingTyLowering.type)
            let storedBox = B.createStoreBox(
              originalValue.copy(self).forward(self), to: box)
            let finalValue = self.pairValueWithCleanup(storedBox)
            argVals.append(finalValue.forward(self))
          }
        } else {
          if originalValue.value is Parameter {
            argVals.append(originalValue.copy(self).forward(self))
          } else {
            argVals.append(originalValue.forward(self))
          }
        }

        lastParent = newParent
      }
      guard let def = self.tc.signature.lookupDefinition(tag.key) else {
        fatalError()
      }
      guard
        case let .dataConstructor(_, _, ty) = def.inside
      else {
          fatalError()
      }
      let (_, endType) = tc.unrollPi(ty.inside)
      let type = self.getLoweredType(endType)
      let dataVal = self.B.createDataInit(tag.key.string, type, argVals)
      return (lastParent, self.pairValueWithCleanup(dataVal))
    default:
      print(body.description)
      fatalError()
    }
  }

  func emitElimAsRValue(
    _ parent: Continuation, _ elim: Elim<TT>
  ) -> (Continuation, ManagedValue) {
    switch elim {
    case let .apply(val):
      return self.emitRValue(parent, val)
    case .project(_):
      fatalError()
    }
  }
}
