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
    return actions(input, context)
  }
}

struct JoinedPass<Input, Intermediate, Output,
                  PassA: PassProtocol, PassB: PassProtocol>: PassProtocol
   where PassA.Input == Input, PassA.Output == Intermediate,
         PassB.Input == Intermediate, PassB.Output == Output {
  let name = "JoinedPass"
  let passA: PassA
  let passB: PassB

  func run(_ input: Input, in context: PassContext) -> Output? {
    return passA.run(input, in: context).flatMap {
      passB.run($0, in: context)
    }
  }
}

func |<Input, Intermediate, Output, PassA: PassProtocol, PassB: PassProtocol>(
  passA: PassA, passB: PassB) -> JoinedPass<Input, Intermediate, Output,
                                            PassA, PassB> {
  return JoinedPass(passA: passA, passB: passB)
}
