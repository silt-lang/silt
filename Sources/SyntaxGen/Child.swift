import Yaml

struct Child {
  let name: String
  let kind: String

  init(name: String, props: [Yaml: Yaml]) {
    guard let kind = props["kind"]?.string else {
      fatalError("invalid child")
    }
    self.kind = kind
    self.name = name
  }
}
