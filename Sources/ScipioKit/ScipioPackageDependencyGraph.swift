struct ScipioPackageDependencyGraph {
    let tree: ScipioBuildNode
    let macroTrees: [ScipioBuildNode]

    init(_ products: [BuildProduct]) {
        guard !products.isEmpty else {
            fatalError("No buildProducts")
        }
        var cache: [String: ScipioBuildNode] = [:]
        let nodes = products.enumerated().map { index, product in
            let node = ScipioBuildNode(nodeIndex: index, buildProduct: product)
            cache[product.target.name] = node
            return node
        }


        self.tree = nodes[0]
        self.macroTrees = nodes.filter { $0.buildProduct.target.type == .macro }

        for node in nodes {
            let product = node.buildProduct
            product.target.dependencies.forEach { dependency in
                let dependencies = switch dependency {
#if compiler(>=6.0)
                case .module(let module, conditions: _):
                    [cache[module.name]]
                case .product(let product, conditions: _):
                    product.modules.map { cache[$0.name] }
#else
                case .target(let target, conditions: _):
                    [cache[module.name]]
                case .product(let product, conditions: _):
                    product.targets.map { cache[$0.name] }
#endif
                }
                dependencies.compactMap { $0 }.forEach {
                    node.dependencyNodes.append($0)
                }
            }
        }
    }
}

final class ScipioBuildNode {
    // A priority
    let nodeIndex: Int
    var dependencyNodes: [ScipioBuildNode] = []
    let buildProduct: BuildProduct

    init(nodeIndex: Int, buildProduct: BuildProduct) {
        self.nodeIndex = nodeIndex
        self.buildProduct = buildProduct
    }

    func orderedDependencies() -> OrderedSet<BuildProduct> {
        let sortedDependencies = recursiveDependencyNodes(isRoot: true).sorted(by: { $0.nodeIndex < $1.nodeIndex }).map(\.buildProduct)
        return OrderedSet(sortedDependencies)
    }

    private func recursiveDependencyNodes(isRoot: Bool) -> [ScipioBuildNode] {
        if buildProduct.target.type == .macro && !isRoot {
            return [self]
        }
        return [self] + dependencyNodes.flatMap { $0.recursiveDependencyNodes(isRoot: false) }
    }

    func retrieveNode(for buildProduct: BuildProduct) -> ScipioBuildNode? {
        return recursiveDependencyNodes(isRoot: true)
            .first(where: { $0.buildProduct == buildProduct })
    }

    func macroNodes() -> [BuildProduct] {
        orderedDependencies().filter { $0.target.type == .macro }
    }
}

import TSCBasic

extension OrderedSet {
    @discardableResult
    public mutating func appendLater(_ newElement: Element) -> Bool {
        remove(newElement)
        return append(newElement)
    }
}
