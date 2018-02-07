/// TypeChecker.swift
///
/// Copyright 2017-2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho
import Lithosphere

public struct TypeCheckerDebugOptions: OptionSet {
  public let rawValue: UInt32
  public init(rawValue: RawValue) {
    self.rawValue = rawValue
  }
  public static let debugMetas =
    TypeCheckerDebugOptions(rawValue: 1 << 0)
  public static let debugNormalizedMetas =
    TypeCheckerDebugOptions(rawValue: 1 << 1)
  public static let debugConstraints =
    TypeCheckerDebugOptions(rawValue: 1 << 2)
}

public final class TypeChecker<PhaseState> {

  var state: State<PhaseState>
  let options: TypeCheckerDebugOptions

  final class State<S> {
    fileprivate var signature: Signature
    fileprivate var environment: Environment
    var state: S

    init(_ signature: Signature, _ env: Environment, _ state: S) {
      self.signature = signature
      self.environment = env
      self.state = state
    }
  }

  public convenience init(_ state: PhaseState,
                          options: TypeCheckerDebugOptions = []) {
    self.init(Signature(), Environment([]), state, options)
  }

  init(_ sig: Signature, _ env: Environment, _ state: PhaseState,
       _ options: TypeCheckerDebugOptions) {
    self.options = options
    self.state = State<PhaseState>(sig, env, state)
  }

  public var signature: Signature {
    return self.state.signature
  }

  public var environment: Environment {
    return self.state.environment
  }

  /// FIXME: Try harder, maybe
  public var wildcardToken: TokenSyntax {
    return TokenSyntax.implicit(.underscore)
  }

  /// FIXME: Try harder, maybe
  public var wildcardName: Name {
    return Name(name: wildcardToken)
  }
}

extension TypeChecker {
  func underExtendedEnvironment<A>(_ ctx: Context, _ f: () -> A) -> A {
    let oldS = self.environment.context
    self.environment.context.append(contentsOf: ctx)
    let val = f()
    self.environment.context = oldS
    return val
  }

  func extendEnvironment(_ ctx: Context) {
    self.environment.context.append(contentsOf: ctx)
  }

  func underEmptyEnvironment<A>(_ f : () -> A) -> A {
    let oldE = self.environment
    self.state.environment = Environment([])
    let val = f()
    self.state.environment = oldE
    return val
  }

  func underNewScope<A>(_ f: () -> A) -> A {
    let oldBlocks = self.environment.scopes
    let oldPending = self.environment.context
    self.environment.scopes.append(.init(self.environment.context, [:]))
    self.environment.context = []
    let result = f()
    self.environment.scopes = oldBlocks
    self.environment.context = oldPending
    return result
  }

  func forEachVariable<T>(in ctx: Context, _ f: (Var) -> T) -> [T] {
    var result = [T]()
    result.reserveCapacity(ctx.count)
    for (ix, (n, _)) in zip((0..<ctx.count).reversed(), ctx).reversed() {
      result.insert(f(Var(n, UInt(ix))), at: 0)
    }
    return result
  }
}

extension TypeChecker {
  func addMeta(
    in ctx: Context, from node: Expr? = nil, expect ty: Type<TT>) -> Term<TT> {
    let metaTy = self.rollPi(in: ctx, final: ty)
    let mv = self.signature.addMeta(metaTy, from: node)
    let metaTm = TT.apply(.meta(mv), [])
    return self.eliminate(metaTm, self.forEachVariable(in: ctx) { v in
      return Elim<TT>.apply(TT.apply(.variable(v), []))
    })
  }
}

extension TypeChecker {
  // Roll a Pi type containing all the types in the context, finishing with the
  // provided type.
  func rollPi(in ctx: Context, final finalTy: Type<TT>) -> Type<TT> {
    var type = finalTy
    for (_, nextTy) in ctx.reversed() {
      type = TT.pi(nextTy, type)
    }
    return type
  }

  // Unroll a Pi type into a telescope of names and types and the final type.
  func unrollPi(
    _ t: Type<TT>, _ ns: [Name]? = nil) -> (Telescope<Type<TT>>, Type<TT>) {
    // FIXME: Try harder, maybe
    let defaultName = Name(name: TokenSyntax(.identifier("_")))
    var tel = Telescope<Type<TT>>()
    var ty = t
    var idx = 0
    while case let .pi(dm, cd) = self.toWeakHeadNormalForm(ty).ignoreBlocking {
      defer { idx += 1 }
      let name = ns?[idx] ?? defaultName
      ty = cd
      tel.append((name, dm))
    }
    return (tel, ty)
  }

  // Takes a Pi-type and replaces all it's elements with metavariables.
  func fillPiWithMetas(_ ty: Type<TT>) -> [Term<TT>] {
    var type = self.toWeakHeadNormalForm(ty).ignoreBlocking
    var metas = [Term<TT>]()
    while true {
      switch type {
      case let .pi(domain, codomain):
        let meta = self.addMeta(in: self.environment.asContext, expect: domain)
        let instCodomain = self.forceInstantiate(codomain, [meta])
        type = self.toWeakHeadNormalForm(instCodomain).ignoreBlocking
        metas.append(meta)
      case .type:
        return metas
      default:
        fatalError("Expected Pi")
      }
    }
  }
}

extension TypeChecker {
  func openContextualType(_ ctxt: ContextualType, _ args: [Term<TT>]) -> TT {
    assert(ctxt.telescope.count == args.count)
    return self.forceInstantiate(ctxt.inside, args)
  }

  func openContextualDefinition(
      _ ctxt: ContextualDefinition, _ args: [Term<TT>]) -> OpenedDefinition {
    func openAccessor<T>(_ accessor: T) -> Opened<T, TT> {
      return Opened<T, TT>(accessor, args)
    }

    func openConstant(_ c: Definition.Constant) -> OpenedDefinition.Constant {
      switch c {
      case .postulate:
        return .postulate
      case let .data(dataCons):
        return .data(dataCons.map { Opened($0, args) })
      case let .record(_, constr, ps):
        return .record(openAccessor(constr), ps.map(openAccessor))
      case let .function(inst):
        return .function(inst)
      }
    }

    precondition(ctxt.telescope.count == args.count)
    switch self.forceInstantiate(ctxt.inside, args) {
    case let .constant(type, constant):
      return .constant(type, openConstant(constant))
    case let .dataConstructor(dataCon, openArgs, type):
      return .dataConstructor(Opened<QualifiedName, TT>(dataCon, args),
                              openArgs, type)
    case let .module(names):
      return .module(names)
    case let .projection(proj, tyName, ctxType):
      return .projection(proj, Opened<QualifiedName, TT>(tyName, args), ctxType)
    case let .letBinding(name, ctxType):
      return .letBinding(Opened<QualifiedName, TT>(name, args), ctxType)
    }
  }

  func openDefinition(
    _ name: QualifiedName, _ args: [Term<TT>]) -> Opened<QualifiedName, TT> {
    let e = self.environment
    guard let firstBlock = e.scopes.first, e.context.isEmpty else {
      fatalError()
    }
    firstBlock.opened[name] = args
    e.scopes[0] = Environment.Scope(firstBlock.context, firstBlock.opened)
    e.context = []
    return Opened<QualifiedName, TT>(name, args)
  }

  func getOpenedDefinition(
      _ name: QualifiedName) -> (Opened<QualifiedName, TT>, OpenedDefinition) {
    func getOpenedArguments(_ name: QualifiedName) -> [TT] {
      precondition(!self.environment.scopes.isEmpty)

      var n = self.environment.context.count
      for block in self.environment.scopes {
        if let args = block.opened[name] {
          return args.map {
            return $0.forceApplySubstitution(.weaken(n), self.eliminate)
          }
        } else {
          n += block.context.count
        }
      }
      fatalError()
    }
    let args = getOpenedArguments(name)
    let contextDef = self.signature.lookupDefinition(name)!
    let def = self.openContextualDefinition(contextDef, args)
    return (Opened<QualifiedName, TT>(name, args), def)
  }

  func getTypeOfOpenedDefinition(_ t: OpenedDefinition) -> Type<TT> {
    switch t {
    case let .constant(ty, _):
      return ty
    case let .dataConstructor(_, _, ct):
      return self.rollPi(in: ct.telescope, final: ct.inside)
    case let .projection(_, _, ct):
      return self.rollPi(in: ct.telescope, final: ct.inside)
    case let .letBinding(_, ct):
      var ty = ct.inside
      for _ in ct.telescope {
        guard
          case let .pi(_, cd) = self.toWeakHeadNormalForm(ty).ignoreBlocking
        else {
          fatalError("Type doesn't contain enough Pi's?")
        }
        ty = cd
      }
      return ty
    case .module(_):
      fatalError()
    }
  }
}
