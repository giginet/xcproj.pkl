import Foundation

func requirePath(_ url: URL, directory: Bool, at context: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue == directory
    else {
        throw ProjectError(
            "\(context): \(directory ? "directory" : "file") does not exist: \(url.path)")
    }
}

func validateAcyclicGraph(_ graph: [String: [String]], label: String) throws {
    var complete = Set<String>()
    func visit(_ node: String, stack: [String]) throws {
        if stack.contains(node) {
            throw ProjectError("\(label) cycle: \((stack + [node]).joined(separator: " → "))")
        }
        if complete.contains(node) { return }
        for next in graph[node] ?? [] { try visit(next, stack: stack + [node]) }
        complete.insert(node)
    }
    for node in graph.keys.sorted() { try visit(node, stack: []) }
}
