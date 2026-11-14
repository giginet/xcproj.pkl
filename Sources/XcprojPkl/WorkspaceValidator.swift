import Foundation

public struct WorkspaceValidation: Sendable {
    public let projectCount: Int
    public let targetCount: Int
}

/// Validates workspace membership and each referenced JSON project.
/// Project-to-project dependency resolution and scheme validation are not performed.
public enum WorkspaceValidator {
    public static func validate(_ workspace: URL) throws -> WorkspaceValidation {
        guard workspace.pathExtension == "xcworkspace" else {
            throw ProjectError("Expected a .xcworkspace directory")
        }
        let data = try Data(
            contentsOf: workspace.appendingPathComponent("contents.xcworkspacedata"))
        let projects = try projectURLs(data: data, workspace: workspace)
        var targetCount = 0
        var diagnostics: [String] = []
        for project in projects {
            do {
                let file = project.appendingPathComponent("project.xcproj")
                if !FileManager.default.fileExists(atPath: file.path),
                    FileManager.default.fileExists(
                        atPath: project.appendingPathComponent("project.pbxproj").path)
                {
                    throw ProjectError(
                        "Only JSON project.xcproj files are supported; found a legacy project")
                }
                targetCount += try ProjectValidator.validate(data: Data(contentsOf: file))
            } catch {
                diagnostics.append("\(project.path): \(error.localizedDescription)")
            }
        }
        if !diagnostics.isEmpty { throw ProjectError(diagnostics) }
        return WorkspaceValidation(projectCount: projects.count, targetCount: targetCount)
    }

    static func projectURLs(data: Data, workspace: URL) throws -> [URL] {
        let reader = WorkspaceXMLReader(workspace: workspace)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        let success = parser.parse()
        if let diagnostic = reader.diagnostic { throw ProjectError(diagnostic) }
        guard success, reader.sawWorkspace else {
            throw ProjectError(
                "Invalid workspace XML: \(parser.parserError?.localizedDescription ?? "missing Workspace root")"
            )
        }
        guard !reader.projects.isEmpty else {
            throw ProjectError("Workspace must contain at least one project")
        }
        var paths = Set<String>()
        for project in reader.projects {
            guard paths.insert(project.path).inserted else {
                throw ProjectError("Duplicate workspace project reference: \(project.path)")
            }
        }
        return reader.projects
    }
}

private final class WorkspaceXMLReader: NSObject, XMLParserDelegate {
    let container: URL
    var groups: [URL]
    var elements: [String] = []
    var projects: [URL] = []
    var diagnostic: String?
    var sawWorkspace = false

    init(workspace: URL) {
        container = URL(
            fileURLWithPath: workspace.deletingLastPathComponent().path, isDirectory: true
        )
        .resolvingSymlinksInPath()
        groups = [container]
    }

    func fail(_ message: String, parser: XMLParser) {
        if diagnostic == nil { diagnostic = message }
        parser.abortParsing()
    }

    func location(_ value: String, directory: Bool) throws -> URL {
        guard let separator = value.firstIndex(of: ":") else {
            throw ProjectError(
                "Workspace location needs a group:, container:, or absolute: prefix: \(value)")
        }
        let prefix = String(value[..<separator])
        let path = String(value[value.index(after: separator)...])
        let base: URL
        switch prefix {
        case "group": base = groups.last!
        case "container": base = container
        case "absolute":
            guard path.hasPrefix("/") else {
                throw ProjectError("Invalid absolute workspace location: \(value)")
            }
            base = container
        default: throw ProjectError("Unsupported workspace location: \(value)")
        }
        if prefix != "absolute", path.hasPrefix("/") {
            throw ProjectError("Expected a relative workspace location: \(value)")
        }
        let resolved = URL(
            fileURLWithPath: path.isEmpty ? "." : path, isDirectory: directory, relativeTo: base
        )
        .standardizedFileURL.resolvingSymlinksInPath()
        return URL(fileURLWithPath: resolved.path, isDirectory: directory)
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        do {
            if elements.isEmpty {
                guard elementName == "Workspace", attributeDict["version"] == "1.0", !sawWorkspace
                else {
                    throw ProjectError("Expected Workspace XML with version 1.0")
                }
                sawWorkspace = true
            } else {
                guard elements.last == "Workspace" || elements.last == "Group" else {
                    throw ProjectError("Unexpected workspace element inside FileRef")
                }
                switch elementName {
                case "Group":
                    groups.append(
                        try location(attributeDict["location"] ?? "group:", directory: true))
                case "FileRef":
                    guard let value = attributeDict["location"] else {
                        throw ProjectError("FileRef is missing location")
                    }
                    let project = try location(value, directory: true)
                    guard project.pathExtension == "xcodeproj" else {
                        throw ProjectError(
                            "Only .xcodeproj workspace references are supported: \(value)")
                    }
                    projects.append(project)
                default: throw ProjectError("Unsupported workspace element: \(elementName)")
                }
            }
            elements.append(elementName)
        } catch { fail(error.localizedDescription, parser: parser) }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Group" { groups.removeLast() }
        if !elements.isEmpty { elements.removeLast() }
    }

    func parser(
        _ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?
    ) {
        fail("XML entity declarations are not supported in workspaces", parser: parser)
    }
    func parser(
        _ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?,
        systemID: String?
    ) {
        fail("XML entity declarations are not supported in workspaces", parser: parser)
    }
}
