/// GIRGen.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Lithosphere
import Moho
import Mantle
import Seismography

public final class GIRGenModule {
  fileprivate var M: GIRModule
  let module: Module
  let environment: Environment
  let signature: Signature
  let tc: TypeChecker<CheckPhaseState>

  struct DelayedContinuation {
    let force: () -> Continuation
  }

  var emittedFunctions: [DeclRef: Continuation] = [:]

  typealias DelayedEmitter = (Continuation) -> ()

  var delayedFunctions: [DeclRef: (Continuation) -> ()] = [:]

  public init(_ root: TopLevelModule) {
    self.module = root.rootModule
    self.M = GIRModule(name: root.name.string)
    self.environment = root.environment
    self.signature = root.signature
    self.tc = root.tc
  }

  public func emitTopLevelModule() -> GIRModule {
    var visitedDecls = Set<QualifiedName>()
    for declKey in self.module.inside {
      guard visitedDecls.insert(declKey).inserted else { continue }

      guard let def = self.signature.lookupDefinition(declKey) else {
        fatalError()
      }
      self.emitContextualDefinition(declKey.string, def)
    }
    return self.M
  }

  func getEmittedFunction(_ ref: DeclRef) -> Continuation? {
    return self.emittedFunctions[ref]
  }
}

extension GIRGenModule {
  func emitContextualDefinition(_ name: String, _ def: ContextualDefinition) {
    precondition(def.telescope.isEmpty, "Cannot gen generics yet")

    switch def.inside {
    case .module(_):
      fatalError()
    case let .constant(ty, constant):
      self.emitContextualConstant(name, constant, ty, def.telescope)
    case .dataConstructor(_, _, _):
      fatalError()
    case .projection(_, _, _):
      fatalError()
    }
  }

  func emitContextualConstant(_ name: String, _ c: Definition.Constant, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch c {
    case let .function(inst):
      self.emitFunction(name, inst, ty, tel)
    case .postulate:
      fatalError()
    case .data(_):
      break
    case .record(_, _, _):
      fatalError()
    }
  }

  func emitFunction(_ name: String, _ inst: Instantiability, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    switch inst {
    case .open:
      return // Nothing to do for opaque functions.
    case let .invertible(body):
      let clauses = body.ignoreInvertibility
      let constant = DeclRef(name, .function)
      let f = Continuation(name: constant.name, type: BottomType.shared)
      self.M.addContinuation(f)
      GIRGenFunction(self, f, ty, tel).emitFunction(clauses)
    }
  }

  func emitFunctionBody(_ constant: DeclRef, _ emitter: @escaping DelayedEmitter) {
    guard let f = self.getEmittedFunction(constant) else {
      self.delayedFunctions[constant] = emitter
      return
    }
    return emitter(f)
  }
}

final class GIRGenFunction {
  var f: Continuation
  let B: IRBuilder
  let params: [(Name, Type<TT>)]
  let returnTy: Type<TT>
  let telescope: Telescope<TT>
  let tc: TypeChecker<CheckPhaseState>
  var varLocs: [Name: Value] = [:]

  init(_ GGM: GIRGenModule, _ f: Continuation, _ ty: Type<TT>, _ tel: Telescope<TT>) {
    self.f = f
    self.B = IRBuilder(module: GGM.M)
    self.telescope = tel
    let (ps, result) = GGM.tc.unrollPi(ty)
    self.params = ps
    self.returnTy = result
    self.tc = GGM.tc
  }

  func emitFunction(_ clauses: [Clause]) {
    let (paramVals, returnCont) = self.buildParameterList()
    self.emitPatternMatrix(clauses, paramVals, returnCont)
  }

  func buildParameterList() -> ([Value], Value) {
    var params = [Value]()
    for (_, paramTy) in self.params {
      let p = self.f.appendParameter(type: BottomType.shared, ownership: .owned)
      params.append(p)
    }
    let ret = self.f.appendParameter(type: BottomType.shared, ownership: .owned)
    return (params, ret)
  }

  func allIrrefutable(_ patterns: [Pattern], _ mask: Set<Int>) -> [Var]? {
    var result = [Var]()
    result.reserveCapacity(patterns.count)
    for (idx, pattern) in patterns.enumerated() {
      guard mask.contains(idx) else {
        result.append(Var(wildcardName, 0))
        continue
      }

      if case .absurd = pattern {
        continue
      }

      guard case let .variable(v) = pattern else {
        return nil
      }
      result.append(v)
    }
    return result
  }

  func emitPatternMatrix(_ matrix: [Clause], _ params: [Value], _ returnCont: Value) {
    guard let firstRow = matrix.first else {
      _ = self.B.createUnreachable(self.f)
      return
    }

    guard !firstRow.patterns.isEmpty else {
      guard let body = firstRow.body else {
        _ = self.B.createUnreachable(self.f)
        return
      }
      let RV = self.emitRValue(body)
      _ = self.B.createApply(self.f, returnCont, [RV])
      return
    }

    var unspecialized = Set<Int>(0..<params.count)
    self.stepSpecialization(self.f, matrix, params, returnCont, &unspecialized)
  }

  func stepSpecialization(
    _ root: Continuation, _ matrix: [Clause], _ params: [Value],
    _ returnCont: Value, _ unspecialized: inout Set<Int>) {
    if matrix.count == 1, let vars = allIrrefutable(matrix[0].patterns, unspecialized) {
      for (idx, v) in vars.enumerated() {
        guard unspecialized.contains(idx) else { continue }
        self.varLocs[v.name] = params[idx]
      }
      guard let body = matrix[0].body else {
        _ = self.B.createUnreachable(self.f)
        return
      }
      self.emitBodyExpr(root, returnCont, body)
      return
    }

    let (colIdx, necessaryHasWilds) = scoreColumns(matrix, params.count, unspecialized)
    guard unspecialized.count == 1 else {
      var specializers = [String: [Clause]]()
      var switchNest = [(String, Value)]()
      var destMap = [(String, Continuation)]()
      var defaultedHeadMatrix = [Clause]()
      var defaultedMatrix = [Clause]()
      var defaults: (cont: Continuation, ref: Value)? = nil
      for (idx, clause) in matrix.enumerated() {
        let pat = colIdx < clause.patterns.count
          ? clause.patterns[colIdx]
          : Pattern.variable(Var(wildcardName, 0))
        switch pat {
        case .absurd:
          fatalError()
        case let .constructor(name, args):
          assert(args.isEmpty)
          if necessaryHasWilds && specializers.count != 0 {
            defaultedHeadMatrix.append(clause)
            continue
          }

          if specializers[name.key.string] == nil {
            let destBB = self.B.buildContinuation(name: root.name + "#col\(colIdx)row\(idx)")
            let ref = self.B.createFunctionRef(destBB)
            destMap.append((name.key.string, destBB))
            switchNest.append((name.key.string, ref))
          }

          specializers[name.key.string, default: []].append(clause)
        case .variable(_):
          if defaults == nil {
            let defaultDestBB = self.B.buildContinuation(name: root.name + "#default")
            let defaultRef = self.B.createFunctionRef(defaultDestBB)
            defaults = (cont: defaultDestBB, ref: defaultRef)
          }
          defaultedMatrix.append(clause)
        }
      }

      _ = self.B.createSwitchConstr(root, params[colIdx], switchNest, defaults?.ref)
      assert(!necessaryHasWilds || destMap.count == 1)
      for (key, dest) in destMap {
        guard var specializedMatrix = specializers[key] else {
          fatalError()
        }
        if necessaryHasWilds && !defaultedHeadMatrix.isEmpty {
          specializedMatrix.append(defaultedMatrix[0])
        }
        unspecialized.remove(colIdx)
        self.stepSpecialization(dest, specializedMatrix, params, returnCont, &unspecialized)
        unspecialized.insert(colIdx)
      }

      if let (defaultDest, _) = defaults {
        unspecialized.remove(colIdx)
        self.stepSpecialization(defaultDest, defaultedHeadMatrix + defaultedMatrix, params, returnCont, &unspecialized)
        unspecialized.insert(colIdx)
      }
      return
    }
    self.emitFinalColumn(root, colIdx, params[colIdx], returnCont, matrix)
  }

  func emitFinalColumn(_ parent: Continuation, _ colIdx: Int, _ param: Value, _ retParam: Value, _ matrix: [Clause]) {
    var dests = [(String, Value)]()
    for (idx, clause) in matrix.enumerated() {
      guard let body = clause.body else {
        fatalError()
      }

      let pat = colIdx < clause.patterns.count
        ? clause.patterns[colIdx]
        : Pattern.variable(Var(wildcardName, 0))
      switch pat {
      case .absurd:
        fatalError()
      case let .variable(v):
//        assert(matrix.count == 1)
        self.varLocs[v.name] = param
        self.emitBodyExpr(parent, retParam, body)
        self.varLocs[v.name] = nil
        return
      case let .constructor(name, pats):
        let destBB = self.B.buildContinuation(name: parent.name + "#col\(colIdx)row\(idx)")
        let destRef = self.B.createFunctionRef(destBB)
//        assert(allIrrefutable(pats) != nil)
        for _ in pats {
          destBB.appendParameter(type: BottomType.shared, ownership: .owned)
        }
        self.emitBodyExpr(destBB, retParam, body)
        dests.append((name.key.string, destRef))
      }
    }
    _ = self.B.createSwitchConstr(parent, param, dests)
  }

  func emitBodyExpr(_ bb: Continuation, _ retParam: Value, _ body: Term<TT>) {
    switch body {
    case let .constructor(name, args):
      guard !args.isEmpty else {
        let retVal = self.B.createDataInitSimple(name.key.string)
        _ = self.B.createApply(bb, retParam, [retVal])
        return
      }
      fatalError()
    case let .apply(head, args):
      switch head {
      case .definition(_):
        fatalError()
      case let .meta(mv):
        guard let bind = self.tc.signature.lookupMetaBinding(mv) else {
          fatalError()
        }
        self.emitBodyExpr(bb, retParam, self.tc.toNormalForm(bind.body))
      case let .variable(v):
        guard let varLoc = self.varLocs[v.name] else {
          fatalError()
        }
        _ = self.B.createApply(bb, retParam, [varLoc])
      }
    default:
      fatalError()
    }
  }

  func scoreColumns(_ pm: [Clause], _ maxWidth: Int, _ keep: Set<Int>) -> (Int, Bool) {
    assert(!pm.isEmpty)

    var scoreMatrix = [(Int, Int)]()
    scoreMatrix.reserveCapacity(maxWidth)
    for i in 0..<maxWidth {
      scoreMatrix.append((i, 0))
    }

    var wildcardColumns = Set<Int>()
    for j in 0..<pm.count {
      for i in 0..<maxWidth {
        guard keep.contains(i) else {
          scoreMatrix[i].1 = Int.min
          continue
        }

        let clause = pm[j]
        guard i < clause.patterns.count else {
          wildcardColumns.insert(i)
          continue
        }

        switch clause.patterns[i] {
        case .absurd:
          fatalError()
        case .variable(_):
          wildcardColumns.insert(i)
          continue
        case .constructor(_, _):
          guard !wildcardColumns.contains(i) else { continue }
          scoreMatrix[i].1 += 1
        }
      }
    }
    let sortedScores = scoreMatrix.sorted(by: { (lhs, rhs) -> Bool in
      return lhs.1 > rhs.1
    })
    assert(!sortedScores.isEmpty)
    return (sortedScores[0].0, wildcardColumns.contains(sortedScores[0].0))
  }

  func emitRValue(_ body: Term<TT>) -> Value {
    fatalError()
  }

  public var wildcardToken: TokenSyntax {
    return TokenSyntax.implicit(.underscore)
  }

  public var wildcardName: Name {
    return Name(name: wildcardToken)
  }
}
