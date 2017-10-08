import Yaml

struct Token {
  enum Kind {
    case associated(String)
    case keyword(String)
    case punctuation(String)
  }
  let caseName: String
  let name: String
  let kind: Kind

  init(name: String, props: [Yaml: Yaml]) {
    self.name = name
    let isKeyword = props["keyword"]?.bool ?? false
    if let text = props["text"]?.string {
      self.kind = isKeyword ? .keyword(text) : .punctuation(text)
    } else if let associatedType = props["associated"]?.string {
      self.kind = .associated(associatedType)
    } else {
      fatalError("cannot figure out token kind")
    }

    let caseName = name.replacingOccurrences(of: "Token", with: "")
      .lowercaseFirstLetter
    self.caseName = "\(caseName)\(isKeyword ? "Keyword" : "")"
  }
}
