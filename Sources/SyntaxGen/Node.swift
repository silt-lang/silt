import Yaml

struct Node {
  let typeName: String
  let kind: String
  let collectionElement: String?
  let children: [Child]

  init(name: String, props: [Yaml: Yaml]) {
    guard let kind = props["kind"]?.string else {
      fatalError("invalid node")
    }
    self.typeName = name
    self.kind = kind == "Syntax" ? "" : kind
    if let childArray = props["children"]?.array {
      self.children = childArray.map { childNode in
        guard let dict = childNode.dictionary else {
          fatalError()
        }
        return Child(name: dict.keys.first!.string!, props: dict.values.first!.dictionary ?? [:])
      }
    } else {
      self.children = []
    }
    if let element = props["element"]?.string {
      self.collectionElement = element
    } else {
      self.collectionElement = nil
    }
  }
}
