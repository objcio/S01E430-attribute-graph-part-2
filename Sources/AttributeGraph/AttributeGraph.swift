// Based on https://www.semanticscholar.org/paper/A-System-for-Efficient-and-Flexible-One-Way-in-C%2B%2B-Hudson/9609985dbef43633f4deb88c949a9776e0cd766b
// https://repository.gatech.edu/server/api/core/bitstreams/3117139f-5de2-4f1f-9662-8723bae97a6d/content

final class AttributeGraph {
    var nodes: [AnyNode] = []
    var currentNode: AnyNode?

    func input<A>(name: String, _ value: A) -> Node<A> {
        let n = Node(name: name, in: self, wrappedValue: value)
        nodes.append(n)
        return n
    }

    func rule<A>(name: String, _ rule: @escaping () -> A) -> Node<A> {
        let n = Node(name: name, in: self, rule: rule)
        nodes.append(n)
        return n
    }

    func graphViz() -> String {
        let nodesStr = nodes.map {
            "\($0.name)\($0.potentiallyDirty ? " [style=dashed]" : "")"
        }.joined(separator: "\n")
        let edges = nodes.flatMap(\.outgoingEdges).map {
            "\($0.from.name) -> \($0.to.name)\($0.pending ? " [style=dashed]" : "")"
        }.joined(separator: "\n")
        return """
        digraph {
        \(nodesStr)
        \(edges)
        }
        """
    }
}

protocol AnyNode: AnyObject {
    var name: String { get }
    var outgoingEdges: [Edge] { get }
    var incomingEdges: [Edge] { get set }
    var potentiallyDirty: Bool { get set }
}

final class Edge {
    unowned var from: AnyNode
    unowned var to: AnyNode
    var pending = false

    init(from: AnyNode, to: AnyNode) {
        self.from = from
        self.to = to
    }
}

final class Node<A>: AnyNode {
    unowned var graph: AttributeGraph
    var name: String
    var rule: (() -> A)?
    var incomingEdges: [Edge] = []
    var outgoingEdges: [Edge] = []
    var potentiallyDirty: Bool = false {
        didSet {
            guard potentiallyDirty, potentiallyDirty != oldValue else { return }
            for e in outgoingEdges {
                e.to.potentiallyDirty = true
            }
        }
    }

    private var _cachedValue: A?

    var wrappedValue: A {
        get {
            recomputeIfNeeded()
            return _cachedValue!
        }
        set {
            assert(rule == nil)
            _cachedValue = newValue
            for e in outgoingEdges {
                e.pending = true
                e.to.potentiallyDirty = true
            }
        }
    }

    func recomputeIfNeeded() {
        if let c = graph.currentNode {
            let edge = Edge(from: self, to: c)
            outgoingEdges.append(edge)
            c.incomingEdges.append(edge)
        }
        if _cachedValue == nil, let rule {
            let previousNode = graph.currentNode
            defer { graph.currentNode = previousNode }
            graph.currentNode = self
            _cachedValue = rule()
        }
    }

    init(name: String, in graph: AttributeGraph, wrappedValue: A) {
        self.name = name
        self.graph = graph
        self._cachedValue = wrappedValue
    }

    init(name: String, in graph: AttributeGraph, rule: @escaping () -> A) {
        self.name = name
        self.graph = graph
        self.rule = rule
    }
}
