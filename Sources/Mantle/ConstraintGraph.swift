/// ConstraintGraph.swift
///
/// Copyright 2018, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

final class ConstraintGraph {
  final class Node {
    class Adjacency {
      var index: Int
      var degree: Int = 0
      var fixedBinding: Bool = false

      init(index: Int) {
        self.index = index
      }

      var isEmpty: Bool {
        return !self.fixedBinding && self.degree == 0
      }
    }

    let meta: Meta
    var constraints: [SolverConstraint] = []
    var constraintIndices: [SolverConstraint: Int] = [:]
    var adjacencies: [Meta] = []
    var adjacencyInfo: [Meta: Adjacency] = [:]
    var equivalenceClass: [Meta] = []
    let index: Int
    weak var parent: ConstraintGraph?

    init(meta: Meta, index: Int, parent: ConstraintGraph) {
      self.meta = meta
      self.index = index
      self.parent = parent
      self.equivalenceClass.append(meta)
    }

    func addConstraint(_ constraint: SolverConstraint) {
      assert(self.constraintIndices[constraint] == nil,
             "Constraint was re-inserted")
      self.constraintIndices[constraint] = self.constraints.count
      self.constraints.append(constraint)
    }

    func addToEquivalenceClass(_ metas: [Meta]) {
      assert(self.meta == self.parent?.getRepresentative(self.meta),
             "Can't extend equivalence class of non-representative")
      self.equivalenceClass.append(contentsOf: metas)
    }

    fileprivate func adjacency(for meta: Meta) -> Adjacency {
      guard let pos = self.adjacencyInfo[meta] else {
        let newAdjacency = Adjacency(index: self.adjacencies.count)
        self.adjacencyInfo[meta] = newAdjacency
        self.adjacencies.append(meta)
        return newAdjacency
      }
      return pos
    }
  }

  var metas: [Meta]
  var metaMap: [Meta: Node]
  var metaParentOrBinding: [Meta: Either<Meta, Meta.Binding>]

  init() {
    self.metas = []
    self.metaMap = [:]
    self.metaParentOrBinding = [:]
  }

  subscript(_ meta: Meta) -> Node {
    if let existingNode = self.metaMap[meta] {
      assert(existingNode.index < self.metas.count)
      assert(self.metas[existingNode.index].hashValue == meta.hashValue)
      return existingNode
    }

    let index = self.metas.count
    let newNode = Node(meta: meta, index: index, parent: self)
    self.metaMap[meta] = newNode
    self.metaParentOrBinding[meta] = .left(meta)
    self.metas.append(meta)

    // If this meta is not the representative of its equivalence class,
    // add it to its representative's set of equivalences.
    let metaRep = getRepresentative(meta)
    guard meta == metaRep else {
      self.mergeMetaNodes(meta, metaRep)
      return newNode
    }

    if let fixed = self.getRepresentativeBinding(metaRep) {
      // Bind this meta to the representative's binding.
      self.bindMeta(meta, to: fixed)
    }

    return newNode
  }

  func addConstraint(_ constraint: SolverConstraint) {
    let constraintMetas = constraint.getMetas()
    for meta in constraintMetas {
      let node = self[meta]

      node.addConstraint(constraint)

      // Record adjacent metas.
      for otherMeta in constraintMetas {
        guard meta != otherMeta else {
          continue
        }

        _ = node.adjacency(for: otherMeta)
      }
    }
  }

  func getRepresentative(_ meta: Meta) -> Meta {
    // Search the meta's equivalence chain for its representative.
    var result = meta
    while
      let fixe = self.metaParentOrBinding[result],
      case let .left(nextTV) = fixe
    {
      // Extract the representative.
      guard nextTV != result else {
        break
      }

      result = nextTV
    }

    guard result != meta else {
      return result
    }

    // Path compression

    var impl = meta
    while
      let fixe = self.metaParentOrBinding[impl],
      case let .left(nextTV) = fixe
    {
      // Extract the representative.
      guard nextTV != result else {
        break
      }

      self.metaParentOrBinding[impl] = .left(result)
      impl = nextTV
    }
    return result
  }

  func bindMeta(_ meta: Meta, to term: Meta.Binding) {
    let rep = self.getRepresentative(meta)
    self.metaParentOrBinding[rep] = .right(term)

    let termMetas = freeMetas(term.body)
    var visitedMetas = Set<Meta>()
    let node = self[meta]
    for termMeta in termMetas {
      guard visitedMetas.insert(termMeta).inserted else {
        continue
      }

      guard meta != termMeta else {
        continue
      }

      self[termMeta].adjacency(for: meta).fixedBinding = true
      node.adjacency(for: termMeta).fixedBinding = true
    }
  }

  func mergeEquivalenceClasses(_ this: Meta, _ other: Meta) {
    // Merge the equivalence classes corresponding to these two metavariables.
    guard this.hashValue <= other.hashValue else {
      return self.mergeEquivalenceClasses(other, this)
    }

    let otherRep = self.getRepresentative(other)
    self.metaParentOrBinding[otherRep] = .left(this)
    self.mergeMetaNodes(this, other)
  }

  private func mergeMetaNodes(_ metaVar1: Meta, _ metaVar2: Meta) {
    assert(getRepresentative(metaVar1) == getRepresentative(metaVar2),
           "Representatives don't match")

    // Retrieve the node for the representative that we're merging into.
    let metaVarRep = getRepresentative(metaVar1)
    let repNode = self[metaVarRep]

    // Retrieve the node for the non-representative.
    assert(metaVar1 == metaVarRep || metaVar2 == metaVarRep,
           "One meta must be the new representative")
    let metaVarNonRep = (metaVar1 == metaVarRep) ? metaVar2 : metaVar1

    // Merge equivalence class from the non-representative meta.
    let nonRepNode = self[metaVarNonRep]
    repNode.addToEquivalenceClass(nonRepNode.equivalenceClass)
  }

  private func getRepresentativeBinding(_ meta: Meta) -> Meta.Binding? {
    let rep = getRepresentative(meta)

    // Check whether it has a binding.
    if
      let fixe = self.metaParentOrBinding[rep],
      case let .right(type) = fixe
    {
      return type
    }

    return nil
  }

  func dump() {
    for meta in self.metas {
      let node = self[meta]
      print("  \(self[meta].meta):")

      // Print constraints.
      if !node.constraints.isEmpty {
        print("    Constraints:")
        let sortedConstraints = node.constraints.sorted(by: { lhs, rhs in
          return lhs.id < rhs.id
        })
        for constraint in sortedConstraints {
          for _ in 0..<6 {
            print(" ", terminator: "")
          }
          print(constraint.debugDescription)
        }
      }

      // Print adjacencies.
      if !node.adjacencies.isEmpty {
        print("    Adjacencies:")
        let sortedAdjacencies = node.adjacencies.sorted(by: { lhs, rhs in
          return lhs.hashValue < rhs.hashValue
        })
        for adjacency in sortedAdjacencies {
          print(" \(adjacency)", terminator: "")

          guard let info = node.adjacencyInfo[adjacency] else {
            continue
          }
          if info.degree > 1 || info.fixedBinding {
            print(" (", terminator: "")
            if info.degree > 1 {
              print("\(info.degree)", terminator: "")
              if info.fixedBinding {
                print(", fixed", terminator: "")
              }
            } else {
              print("fixed", terminator: "")
            }
            print(")", terminator: "")
          }
        }
        print("")
      }

      // Print equivalence class.
      if self.getRepresentative(node.meta) == node.meta &&
        node.equivalenceClass.count > 1 {
        print("    Equivalence class:", terminator: "")
        for eqClass in node.equivalenceClass {
          print(" \(eqClass)", terminator: "")
        }
        print("")
      }
    }
  }
}
