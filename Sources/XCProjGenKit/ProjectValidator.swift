import Foundation
import XcodeProjectFormat

/// Checks the Apple schema and local graph references in Pkl-rendered documents.
/// It does not evaluate build settings, external projects, or Swift package resolution.
enum ProjectValidator {
    static func validate(data: Data) throws -> Int {
        let project = try XCSchema.Project(jsonRepresentation: data)
        try validate(project)
        return project.targets.count
    }

    private static func validate(_ project: XCSchema.Project) throws {
        var diagnostics: [String] = []
        var ids = Set<String>()
        var treeIDs = Set<String>()
        var paths: [[String]: Int] = [:]
        var phaseIDs = Set<String>()
        var versionGroups: [(XCSchema.VersionGroup, [String])] = []
        let targets = Dictionary(grouping: project.targets, by: \.name)
        let configs = project.configurations.map { $0.name.rawValue }
        if Set(configs).count != configs.count {
            diagnostics.append("Duplicate build configuration names")
        }
        if !configs.contains(project.defaultConfigurationName.rawValue) {
            diagnostics.append(
                "Unknown default build configuration: \(project.defaultConfigurationName.rawValue)")
        }
        func registerID(_ id: XCSchema.ObjectID?, context: String) {
            guard let id else { return }
            if id.rawValue.isEmpty { diagnostics.append("\(context): empty object ID") }
            if !ids.insert(id.rawValue).inserted {
                diagnostics.append("Duplicate object ID '\(id.rawValue)' at \(context)")
            }
        }
        func checkTarget(_ name: String, context: String) {
            if targets[name]?.count != 1 {
                diagnostics.append("\(context): unknown or ambiguous target '\(name)'")
            }
        }
        registerID(project.objectID, context: "project")
        registerID(project.rootGroupDebugID, context: "root group")
        registerID(project.configurationListDebugID, context: "project configuration list")
        for config in project.configurations {
            registerID(config.objectID, context: "configuration \(config.name.rawValue)")
        }
        for target in project.targets {
            registerID(target.commonProperties.objectID, context: "target \(target.name)")
            registerID(
                target.commonProperties.configurationListDebugID,
                context: "\(target.name) configuration list")
            for rule in target.commonProperties.buildRules {
                registerID(rule.objectID, context: "\(target.name) build rule")
            }
            let specializedNames = target.commonProperties.specializedConfigurations.map {
                $0.name.rawValue
            }
            if Set(specializedNames).count != specializedNames.count {
                diagnostics.append("\(target.name): duplicate specialized configuration names")
            }
            for configuration in target.commonProperties.specializedConfigurations {
                if !configs.contains(configuration.name.rawValue) {
                    diagnostics.append(
                        "\(target.name): unknown configuration '\(configuration.name.rawValue)'")
                }
                registerID(configuration.objectID, context: "\(target.name) configuration")
            }
            if let host = target.commonProperties.testHostTarget {
                checkTarget(host.targetName, context: "\(target.name) test host")
            }
            for phase in target.commonProperties.buildPhases {
                let properties = phase.properties
                registerID(properties.objectID, context: "\(target.name) build phase")
                if let id = properties.objectID { phaseIDs.insert(id.rawValue) }
            }
        }
        func checkPhase(_ reference: XCSchema.ProjectBuildPhaseReference) {
            switch reference {
            case .objectID(let id):
                if !phaseIDs.contains(id.rawValue) {
                    diagnostics.append("Unknown build phase ID: \(id.rawValue)")
                }
            case .named(let target, let kind, let name):
                checkTarget(target.targetName, context: "Build phase reference")
                if let target = targets[target.targetName]?.first {
                    let matches = target.commonProperties.buildPhases.filter {
                        $0.kind == kind && (name == nil || $0.properties.name == name)
                    }
                    if matches.count != 1 {
                        diagnostics.append(
                            "Unknown or ambiguous build phase: \(reference.description)")
                    }
                }
            }
        }
        func checkBuildFiles(_ files: [XCSchema.ProjectBuildFile]) {
            for file in files {
                registerID(file.objectID, context: "build file")
                checkPhase(file.buildPhase)
            }
        }
        func checkPackageBuildFile(_ file: XCSchema.TargetBuildFile, target: XCSchema.Target) {
            registerID(file.objectID, context: "\(target.name) package build file")
            let matches = target.commonProperties.buildPhases.filter { phase in
                switch file.buildPhase {
                case .objectID(let id): phase.properties.objectID == id
                case .named(let kind, let name):
                    phase.kind == kind && (name == nil || phase.properties.name == name)
                }
            }
            if matches.count != 1 {
                diagnostics.append(
                    "\(target.name): unknown or ambiguous package build phase '\(file.buildPhase)'")
            }
        }
        func addTreeNode(name: String, id: XCSchema.ObjectID?, parent: [String]) {
            paths[parent + [name], default: 0] += 1
            registerID(id, context: "file tree \((parent + [name]).joined(separator: "/"))")
            if let id { treeIDs.insert(id.rawValue) }
        }
        func walk(_ references: [XCSchema.Reference], parent: [String]) {
            for reference in references {
                switch reference {
                case .fileReference(let file):
                    addTreeNode(
                        name: (file.path.path as NSString).lastPathComponent, id: file.objectID,
                        parent: parent)
                    checkBuildFiles(file.buildFiles)
                case .group(let group):
                    addTreeNode(name: group.name, id: group.objectID, parent: parent)
                    walk(group.children, parent: parent + [group.name])
                case .folder(let folder):
                    addTreeNode(
                        name: (folder.path.path as NSString).lastPathComponent, id: folder.objectID,
                        parent: parent)
                    for target in folder.targets {
                        checkTarget(target.targetName, context: "Folder \(folder.path.path)")
                    }
                    for exception in folder.membershipExceptions {
                        switch exception {
                        case .target(let value):
                            checkTarget(value.target.targetName, context: "Folder exception")
                        case .buildPhase(let value): checkPhase(value.buildPhase)
                        }
                    }
                case .variantGroup(let group):
                    addTreeNode(name: group.name, id: group.objectID, parent: parent)
                    checkBuildFiles(group.buildFiles)
                    walk(
                        group.children.map(XCSchema.Reference.fileReference),
                        parent: parent + [group.name])
                case .versionGroup(let group):
                    versionGroups.append((group, parent + [group.name]))
                    addTreeNode(name: group.name, id: group.objectID, parent: parent)
                    checkBuildFiles(group.buildFiles)
                    walk(
                        group.children.map(XCSchema.Reference.fileReference),
                        parent: parent + [group.name])
                }
            }
        }
        walk(project.topLevelReferences, parent: [])
        func resolve(_ path: XCSchema.NamePath, relativeTo parent: [String] = []) -> [String] {
            var components = parent
            for component in path.components {
                switch component {
                case .child(let name): components.append(name)
                case .relative(.current): break
                case .relative(.parent): if !components.isEmpty { components.removeLast() }
                }
            }
            return components
        }
        func checkTreeReference(_ reference: XCSchema.GroupTreeReference, context: String) {
            switch reference {
            case .objectID(let id):
                if !treeIDs.contains(id.rawValue) {
                    diagnostics.append("\(context): unknown file tree ID '\(id.rawValue)'")
                }
            case .namePath(let path):
                let components = resolve(path)
                if paths[components] != 1 {
                    diagnostics.append(
                        "\(context): unknown or ambiguous file reference '\(reference.description)'"
                    )
                }
            }
        }
        if let products = project.productsGroup {
            checkTreeReference(products, context: "Products group")
        }
        for (group, path) in versionGroups {
            guard let current = group.currentVersion else { continue }
            let valid: Bool
            switch current {
            case .objectID(let id):
                valid = group.children.filter { $0.objectID == id }.count == 1
            case .namePath(let reference):
                let children = Set(
                    group.children.map { path + [($0.path.path as NSString).lastPathComponent] })
                // Version names are relative to their group. Also accept an explicit
                // root-relative tree reference if it names a direct child of that group.
                valid = [resolve(reference, relativeTo: path), resolve(reference)].contains {
                    children.contains($0) && paths[$0] == 1
                }
            }
            if !valid {
                diagnostics.append(
                    "Version group \(group.name): current version '\(current)' must name a child file"
                )
            }
        }
        for product in project.importedProducts {
            checkTreeReference(product.project, context: "Imported product \(product.path)")
            checkBuildFiles(product.buildFiles)
        }
        for config in project.configurations {
            if let file = config.file {
                checkTreeReference(file.anchor, context: "Configuration \(config.name.rawValue)")
            }
        }
        var graph: [String: [String]] = [:]
        for target in project.targets {
            if let product = target.commonProperties.product {
                checkTreeReference(product, context: "Product of \(target.name)")
            }
            for config in target.commonProperties.specializedConfigurations {
                if let file = config.file {
                    checkTreeReference(
                        file.anchor, context: "\(target.name) configuration \(config.name.rawValue)"
                    )
                }
            }
            graph[target.name] = []
            for member in target.commonProperties.packageProductTargetMembers {
                checkPackageBuildFile(member.buildFile, target: target)
            }
            for dependency in target.commonProperties.dependencies {
                switch dependency {
                case .localTarget(let reference, _):
                    checkTarget(reference.targetName, context: "Dependency of \(target.name)")
                    graph[target.name, default: []].append(reference.targetName)
                case .remoteTarget(let reference, _):
                    checkTreeReference(
                        reference.project, context: "Remote dependency of \(target.name)")
                case .package: break
                }
            }
        }
        do { try validateTargetGraph(graph) } catch {
            diagnostics.append(String(describing: error))
        }
        if !diagnostics.isEmpty { throw ProjectError(diagnostics.sorted()) }
    }
}

extension XCSchema.BuildPhase {
    fileprivate var properties: XCSchema.BuildPhaseProperties {
        switch self {
        case .frameworks(let p), .headers(let p), .javaArchive(let p), .resources(let p),
            .rez(let p),
            .sources(let p):
            p
        case .appleScript(let p): p.baseProperties
        case .copy(let p): p.baseProperties
        case .script(let p): p.baseProperties
        }
    }
}

private func validateTargetGraph(_ graph: [String: [String]]) throws {
    var complete = Set<String>()
    func visit(_ node: String, stack: [String]) throws {
        if stack.contains(node) {
            throw ProjectError(
                "Target dependency cycle: \((stack + [node]).joined(separator: " → "))")
        }
        if complete.contains(node) { return }
        for next in graph[node] ?? [] { try visit(next, stack: stack + [node]) }
        complete.insert(node)
    }
    for node in graph.keys.sorted() { try visit(node, stack: []) }
}
