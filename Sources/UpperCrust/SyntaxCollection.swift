public class SyntaxCollection<Element: Syntax>: Syntax {
    public subscript(_ index: Int) -> Element? {
        return child(at: index) as? Element
    }

    public convenience init(_ elements: [Element]) {
        let rawElements = elements.map { $0.raw }
        let raw = RawSyntax.node(type(of: self).kind, rawElements, .present)
        let data = SyntaxData(raw: raw, parent: nil, indexInParent: 0)
        self.init(root: data, data: data)
    }
}
