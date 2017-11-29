/// Pass.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation
import Lithosphere

class PassContext {
  let timer = PassTimer()
  let engine: DiagnosticEngine

  init(engine: DiagnosticEngine) {
    self.engine = engine
  }
}

protocol PassProtocol {
  associatedtype Input
  associatedtype Output

  var name: String { get }
  func run(_ input: Input, in context: PassContext) -> Output?
}

struct Pass<In, Out>: PassProtocol {
  typealias Input = In
  typealias Output = Out

  let name: String
  let actions: (Input, PassContext) -> Output?

  init(name: String, actions: @escaping (Input, PassContext) -> Output?) {
    self.name = name
    self.actions = actions
  }

  func run(_ input: In, in context: PassContext) -> Out? {
    return context.timer.measure(pass: name) {
      actions(input, context)
    }
  }
}

struct PassComposition<Input, Output,
                       PassA: PassProtocol, PassB: PassProtocol>: PassProtocol
   where PassA.Input == Input, PassA.Output == PassB.Input,
         PassB.Output == Output {
  let name = "PassComposition"
  let passA: PassA
  let passB: PassB

  func run(_ input: Input, in context: PassContext) -> Output? {
    return passA.run(input, in: context).flatMap {
      passB.run($0, in: context)
    }
  }
}

infix operator |> : AdditionPrecedence

func |><Input, Output, PassA: PassProtocol, PassB: PassProtocol>(
  passA: PassA, passB: PassB) -> PassComposition<Input, Output, PassA, PassB> {
  return PassComposition(passA: passA, passB: passB)
}
