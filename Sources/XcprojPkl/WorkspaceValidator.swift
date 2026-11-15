import Foundation

public struct WorkspaceValidation: Sendable {
    public let projectCount: Int
}

/// Validates workspace XML and referenced directories without reading project contents.
public enum WorkspaceValidator {
    public static func validate(_ workspace: URL) throws -> WorkspaceValidation {
        guard workspace.pathExtension == "xcworkspace" else {
            throw ProjectError("Expected a .xcworkspace directory")
        }
        let data = try Data(
            contentsOf: workspace.appendingPathComponent("contents.xcworkspacedata"))
        let projects = try projectURLs(data: data, workspace: workspace)
        for project in projects {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else {
                throw ProjectError("Expected an existing .xcodeproj directory: \(project.path)")
            }
        }
        return WorkspaceValidation(projectCount: projects.count)
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

    func location(_ value: String) throws -> URL {
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
        let resolved = canonicalFileURL(
            URL(
                fileURLWithPath: path.isEmpty ? "." : path, isDirectory: true, relativeTo: base
            ))
        return URL(fileURLWithPath: resolved.path, isDirectory: true)
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
                        try location(attributeDict["location"] ?? "group:"))
                case "FileRef":
                    guard let value = attributeDict["location"] else {
                        throw ProjectError("FileRef is missing location")
                    }
                    let project = try location(value)
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
