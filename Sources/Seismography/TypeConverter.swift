/// TypeConverter.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.
import Moho

public class TypeConverter {
  public weak var module: GIRModule?

  /// Defines an area where types are registered as they are being lowered.
  /// This is necessary so recursive types can hit a base case and use their
  /// existing, incomplete GIR definition.
  public var inProgressLowerings = [QualifiedName: GIRType]()

  public class Lowering {

  }

  init() {}
}
