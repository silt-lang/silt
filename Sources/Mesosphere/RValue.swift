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
    _ parent: Continuation, _ body: Term<TT>, _ type: Type<TT>? = nil
  ) -> (Continuation, ManagedValue) {
    switch body {
    case let .apply(head, args):
      switch head {
      case let .definition(defName):
        let constant = DeclRef(defName.key.string, .function)
        let callee = self.B.module.lookupContinuation(constant)!
        let calleeRef = self.B.createFunctionRef(callee)
        return self.completeApply(defName.key.string,
                                  parent,
                                  ManagedValue.unmanaged(calleeRef),
                                  args,
                                  callee.returnValueType,
                                  self.f == callee,
                                  callee.indirectReturnParameter)
      case let .meta(mv):
        guard let bind = self.tc.signature.lookupMetaBinding(mv) else {
          fatalError()
        }
        guard let bindTy = self.tc.signature.lookupMetaType(mv) else {
          fatalError()
        }
        return self.emitRValue(parent, bind.internalize, bindTy)
      case let .variable(v):
        guard let varLocVal = self.lookupVariable(v) else {
          fatalError()
        }
        if let fnType = varLocVal.type as? FunctionType {
          return self.completeApply(v.name.description,
                                    parent,
                                    ManagedValue.unmanaged(varLocVal),
                                    args,
                                    fnType.returnType)
        } else if varLocVal.type is BoxType {
          let lowering = self.lowerType(varLocVal.type)
          let projected = self.B.createProjectBox(varLocVal,
                                                  type: lowering.type)
          if !lowering.addressOnly {
            let loadVal = self.B.createLoad(projected, .copy)
            return (parent, ManagedValue.unmanaged(loadVal))
          } else {
            let projected = self.B.createProjectBox(varLocVal,
                                                    type: lowering.type)
            return (parent, ManagedValue.unmanaged(projected))
          }
        } else {
          assert(args.isEmpty)
          return (parent, ManagedValue.unmanaged(varLocVal))
        }
      }
    case let .constructor(tag, args):
      return self.emitConstructorAsRValue(parent, body, type, tag, args)
    case let .lambda(cloBody):
      guard let cloTy = type else {
        fatalError()
      }
      // Emit the closure body.
      var mangler = GIRMangler()
      self.f.mangle(into: &mangler)
//      self.lowerType(cloTy).type.mangle(into: &mangler)
      mangler.append("fU")
      let ident = SyntaxFactory.makeIdentifier(mangler.finalize())
      let cloF = Continuation(name: QualifiedName(name: Name(name: ident)))
      self.B.module.addContinuation(cloF)

      GIRGenFunction(self.GGM, cloF, cloTy, self.telescope).emitClosure(cloBody)

      // Generate the closure value (if any) for the closure expr's function
      // reference.
      let cloRef = self.B.createFunctionRef(cloF)
      let result = self.B.createThicken(cloRef)
      return (parent, ManagedValue.unmanaged(result))
    default:
      print(body.description)
      fatalError()
    }
  }

  private func completeApply(
    _ name: String,
    _ parent: Continuation,
    _ calleeRef: ManagedValue,
    _ args: [Elim<TT>],
    _ returnValueType: GIRType,
    _ recursive: Bool = false,
    _ indirectReturnParameter: Parameter? = nil
  ) -> (Continuation, ManagedValue) {
    let applyDest = self.B.buildBBLikeContinuation(
      base: self.f.name, tag: "_apply_\(name)")
    let applyDestRef: Value
    // Special Case: Recursive calls have a known return point.
    if recursive {
      applyDestRef = self.f.parameters.last!
    } else {
      applyDestRef = self.B.createFunctionRef(applyDest)
    }
    let param = applyDest.appendParameter(type: returnValueType)
    var lastParent = parent
    var argVals = [Value]()
    argVals.reserveCapacity(args.count)
    for arg in args {
      let (newParent, value) = self.emitElimAsRValue(lastParent, arg)
      argVals.append(value.forward(self))
      lastParent = newParent
    }
    // Account for the indirect return convention's buffer parameter.
    if let indirect = indirectReturnParameter {
      // Alloca in our frame.
      let alloca = B.createAlloca(indirect.type)
      argVals.append(alloca)
      // Dealloca on the return edge.
      //
      // FIXME: Can we do this with the cleanup stack somehow?
      applyDest.appendCleanupOp(self.B.createDealloca(alloca))
    }
    argVals.append(applyDestRef)
    _ = self.B.createApply(lastParent, calleeRef.forward(self), argVals)
    // Special Case: Recursive calls have a known destination block, namely
    // bb0.  We can just stop chuzzling and erase the block we would have
    // continued with.
    if recursive {
      self.B.module.removeContinuation(applyDest)
    }
    return (applyDest, ManagedValue.unmanaged(param))
  }

  private func emitConstructorAsRValue(
    _ parent: Continuation, _ body: Term<TT>, _ type: Type<TT>? = nil,
    _ tag: Opened<QualifiedName, TT>, _ args: [Term<TT>]
  ) -> (Continuation, ManagedValue) {
    var lastParent = parent
    var argVals = [Value]()
    argVals.reserveCapacity(args.count)
    let payloadTypes = self.getPayloadTypeOfConstructorsIgnoringBoxing(tag)
    assert(payloadTypes.count == args.count)

    var inits = [TupleElementAddressOp?]()
    if let payloadBoxTy = self.getPayloadTypeOfConstructors(tag) as? BoxType {
      let box = B.createAllocBox(payloadBoxTy.underlyingType)
      let addr = B.createProjectBox(box, type: payloadBoxTy.underlyingType)
      for idx in 0..<payloadTypes.count {
        inits.append(B.createTupleElementAddress(addr, idx))
      }
      argVals.append(box)
    } else {
      for _ in 0..<payloadTypes.count {
        inits.append(nil)
      }
    }

    var storesToForce = [Value]()
    for ((ty, arg), dest) in zip(zip(payloadTypes, args), inits) {
      let (newParent, originalValue) = self.emitRValue(lastParent, arg)
      if ty is BoxType {
        let underlyingTyLowering = self.lowerType(ty)
        if underlyingTyLowering.addressOnly {
          let addr: Value = dest ?? { () -> Value in
            let box = B.createAllocBox(underlyingTyLowering.type)
            return B.createProjectBox(box, type: underlyingTyLowering.type)
          }()
          let storedBox = B.createStore(
            originalValue.forward(self), to: addr)
          let finalValue = self.pairValueWithCleanup(storedBox)
          argVals.append(finalValue.forward(self))
        } else {
          let addr: Value = dest ?? { () -> Value in
            let box = B.createAllocBox(underlyingTyLowering.type)
            return B.createProjectBox(box, type: underlyingTyLowering.type)
            }()
          let storedBox = B.createStore(
            originalValue.copy(self).forward(self), to: addr)
          let finalValue = self.pairValueWithCleanup(storedBox)
          argVals.append(finalValue.forward(self))
        }
      } else {
        if originalValue.value is Parameter {
          if let dest = dest {
            let store =
              B.createStore(originalValue.copy(self).forward(self), to: dest)
            storesToForce.append(store)
          } else {
            argVals.append(originalValue.copy(self).forward(self))
          }
        } else {
          if let dest = dest {
            let store = B.createStore(originalValue.forward(self), to: dest)
            storesToForce.append(store)
          } else {
            argVals.append(originalValue.forward(self))
          }
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
    let argValue: Value? = self.formEnumArgumentValue(argVals)
    let dataVal = self.B.createDataInit(tag.key.string, type, argValue.map {
      B.createForceEffects($0, storesToForce)
    })
    return (lastParent, self.pairValueWithCleanup(dataVal))
  }
}

extension GIRGenFunction {
  func formEnumArgumentValue(_ payload: [Value]) -> Value? {
    guard let first = payload.first else {
      return nil
    }
    if payload.count == 1 {
      return first
    } else {
      return self.B.createTuple(payload)
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
