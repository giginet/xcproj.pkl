import Foundation
import PklRuntimeResources

/// Fully rendered and validated artifacts. Compiling never writes output files.
public struct GenerationPlan: Sendable {
    public struct File: Sendable {
        public let data: Data
        public let destination: URL
        public let isProject: Bool
        public let isScheme: Bool
        public let bundle: URL
    }
    public let files: [File]
    public let destination: URL
    public let projectCount: Int
    public let targetCount: Int
    public var projects: [File] { files.filter(\.isProject) }

    /// Check caller-supplied properties before dependency resolution or evaluation.
    public static func validateProperties(_ properties: [String]) throws {
        for property in properties {
            guard let separator = property.firstIndex(of: "="), separator != property.startIndex
            else {
                throw ProjectError("Expected --property key=value, got '\(property)'")
            }
            guard !property[..<separator].hasPrefix("xcproj.internal.") else {
                throw ProjectError("The xcproj.internal. property namespace is reserved")
            }
        }
    }

    /// outputDirectory replaces the root bundle parent; its name comes from Pkl.
    public static func compile(
        source: URL, tool: PklTool = PklTool(), properties: [String] = [],
        outputDirectory: URL? = nil
    ) throws -> GenerationPlan {
        try validateProperties(properties)
        // Canonicalize the entry before Pkl resolves its own relative imports.
        let snapshot = try tool.evaluate(canonicalFileURL(source), properties: properties)
        let manifest = try JSONDecoder().decode(InputManifest.self, from: snapshot)
        let facts = try HostFacts.observe(manifest, outputDirectory: outputDirectory)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xcproj-render-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let request = temporary.appendingPathComponent("snapshot.json")
        let host = temporary.appendingPathComponent("facts.json")
        try snapshot.write(to: request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(facts).write(to: host)
        let rendered = try tool.evaluate(
            PklRuntimeResources.renderer,
            properties: [
                "xcproj.internal.request=\(request.absoluteString)",
                "xcproj.internal.hostFacts=\(host.absoluteString)",
            ], expression: "renderPlanText")
        return try accept(rendered, manifest: manifest, facts: facts)
    }

    private struct WirePlan: Decodable {
        struct File: Decodable {
            let artifactId: String
            let kind: ArtifactKind
            let destinationUri: String
            let text: String
        }
        let protocolVersion: Int
        let rootArtifactId: String
        let projectCount: Int
        let targetCount: Int
        let files: [File]
    }

    static func accept(_ data: Data, manifest: InputManifest, facts: HostFacts) throws
        -> GenerationPlan
    {
        let plan = try JSONDecoder().decode(WirePlan.self, from: data)
        guard plan.protocolVersion == 1, plan.rootArtifactId == manifest.rootArtifactId,
            plan.files.count == manifest.artifacts.count,
            Set(plan.files.map(\.artifactId)) == Set(manifest.artifacts.map(\.id))
        else { throw ProjectError("Rendered plan does not match Snapshot artifacts") }
        var files: [File] = []
        var targetCount = 0
        for file in plan.files {
            let artifact = manifest.artifacts.first { $0.id == file.artifactId }!
            guard file.kind == artifact.kind,
                file.destinationUri == facts.paths[artifact.filePathId]?.canonicalUri
            else {
                throw ProjectError("Rendered artifact destination or kind mismatch: \(artifact.id)")
            }
            let destination = try localFileURL(file.destinationUri)
            let bundle = facts.paths[artifact.bundlePathId]!.url
            if file.kind == .scheme {
                guard destination.pathExtension == "xcscheme",
                    destination.deletingLastPathComponent().path
                        == bundle.appendingPathComponent("xcshareddata/xcschemes").path
                else { throw ProjectError("Invalid scheme filename: \(destination.path)") }
            } else {
                let expectedName =
                    file.kind == .project ? "project.xcproj" : "contents.xcworkspacedata"
                guard destination.lastPathComponent == expectedName,
                    destination.deletingLastPathComponent().path == bundle.path
                else { throw ProjectError("Invalid artifact filename: \(destination.path)") }
            }
            let bytes = Data(file.text.utf8)
            if file.kind == .project { targetCount += try ProjectValidator.validate(data: bytes) }
            files.append(
                File(
                    data: bytes, destination: destination, isProject: file.kind == .project,
                    isScheme: file.kind == .scheme, bundle: bundle))
        }
        let projects = files.filter(\.isProject)
        guard plan.projectCount == projects.count, plan.targetCount == targetCount else {
            throw ProjectError("Rendered plan counts do not match validated projects")
        }
        // Validate XML against this plan, before the referenced projects exist on disk.
        if let workspace = files.first(where: { !$0.isProject && !$0.isScheme }) {
            let references = try WorkspaceValidator.projectURLs(
                data: workspace.data, workspace: workspace.bundle)
            guard Set(references.map(\.path)) == Set(projects.map { $0.bundle.path }) else {
                throw ProjectError("Workspace references do not match generated projects")
            }
        }
        for scheme in files where scheme.isScheme {
            try validateScheme(scheme, projects: projects)
        }
        guard Set(files.map { $0.destination.path }).count == files.count else {
            throw ProjectError("Duplicate output file paths")
        }
        let bundles = files.filter { !$0.isScheme }.map { $0.bundle.path }
        guard Set(bundles).count == bundles.count else {
            throw ProjectError("Duplicate output paths")
        }
        for a in bundles {
            for b in bundles where a != b && a.hasPrefix(b + "/") {
                throw ProjectError("Nested output paths: \(a) and \(b)")
            }
        }
        let root = manifest.artifacts.first { $0.id == manifest.rootArtifactId }!
        return GenerationPlan(
            files: files, destination: facts.paths[root.bundlePathId]!.url,
            projectCount: projects.count, targetCount: targetCount)
    }

    @discardableResult
    public func write() throws -> Bool {
        for file in files {
            if file.isProject,
                FileManager.default.fileExists(
                    atPath: file.bundle.appendingPathComponent("project.pbxproj").path)
            {
                throw ProjectError(
                    "Refusing to overwrite a legacy project containing project.pbxproj: \(file.bundle.path)"
                )
            }
            try validateOutputFile(file.destination)
        }
        var changed = false
        for file in files {
            if try writeIfChanged(file.data, to: file.destination) { changed = true }
        }
        return changed
    }

    private static func validateScheme(_ scheme: File, projects: [File]) throws {
        let reader = SchemeXMLReader()
        let parser = XMLParser(data: scheme.data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.root == "Scheme", !reader.hasEntityDeclaration else {
            throw ProjectError("Invalid scheme XML: \(scheme.destination.path)")
        }
        var targetIDs: [String: Set<String>] = [:]
        for project in projects {
            let json = try JSONSerialization.jsonObject(with: project.data) as? [String: Any]
            let targets = json?["targets"] as? [[String: Any]] ?? []
            targetIDs[project.bundle.path] = Set(targets.compactMap { $0["id"] as? String })
        }
        for reference in reader.references {
            guard let container = reference["ReferencedContainer"],
                container.hasPrefix("container:"),
                let identifier = reference["BlueprintIdentifier"]
            else { throw ProjectError("Invalid scheme buildable reference") }
            let path = String(container.dropFirst("container:".count))
            let project = canonicalFileURL(
                URL(fileURLWithPath: path, relativeTo: scheme.bundle.deletingLastPathComponent()))
            guard targetIDs[project.path]?.contains(identifier) == true else {
                throw ProjectError("Scheme references an unknown project or target: \(container)")
            }
        }
    }
}

private final class SchemeXMLReader: NSObject, XMLParserDelegate {
    var root: String?
    var references: [[String: String]] = []
    var hasEntityDeclaration = false

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        if root == nil { root = elementName }
        if elementName == "BuildableReference" { references.append(attributeDict) }
    }

    func parser(
        _ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?
    ) {
        hasEntityDeclaration = true
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?,
        systemID: String?
    ) {
        hasEntityDeclaration = true
        parser.abortParsing()
    }
}
