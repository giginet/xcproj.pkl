import Foundation

struct WorkspaceSpec: Decodable {
  let kind: String
  let schemaVersion: Int
  let name: String
  let workspaceDir: String
  let projects: [WorkspaceProjectSpec]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case kind, schemaVersion, name, workspaceDir, projects
  }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    kind = try c.decode(String.self, forKey: .kind)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    name = try c.decode(String.self, forKey: .name)
    workspaceDir = try c.decodeIfPresent(String.self, forKey: .workspaceDir) ?? "."
    projects = try c.decode([WorkspaceProjectSpec].self, forKey: .projects)
  }
}

struct WorkspaceProjectSpec: Decodable {
  let key: String
  let source: String
  let project: ProjectSpec
  enum CodingKeys: String, CodingKey, CaseIterable { case key, source, project }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    key = try c.decode(String.self, forKey: .key)
    source = try c.decode(String.self, forKey: .source)
    project = try c.decode(ProjectSpec.self, forKey: .project)
  }
}

public struct GeneratedWorkspace: Sendable {
  public let data: Data
  public let destination: URL
  public let projects: [GeneratedProject]
  public var targetCount: Int { projects.reduce(0) { $0 + $1.targetCount } }

  /// Validate every destination before writing. Each file is atomic; the entire set is not.
  /// Unrelated bundle contents, including shared schemes, are retained.
  @discardableResult
  public func write() throws -> Bool {
    let file = destination.appendingPathComponent("contents.xcworkspacedata")
    try validateOutputFile(file)
    for project in projects { try project.validateDestination() }
    var changed = false
    for project in projects {
      if try project.write() { changed = true }
    }
    if try writeIfChanged(data, to: file) { changed = true }
    return changed
  }
}

public struct WorkspaceGenerator: Sendable {
  public init() {}

  public func compile(json: Data, specDirectory: URL, output: URL? = nil) throws
    -> GeneratedWorkspace
  {
    let spec = try JSONDecoder().decode(WorkspaceSpec.self, from: json)
    guard spec.kind == "workspace", spec.schemaVersion == 1 else {
      throw ProjectError("Unsupported workspace kind or schemaVersion")
    }
    try validateName(spec.name, at: "workspace.name")
    guard !spec.projects.isEmpty else {
      throw ProjectError("Workspace must contain at least one project")
    }
    let directory = URL(fileURLWithPath: specDirectory.path, isDirectory: true)
    let root = URL(fileURLWithPath: spec.workspaceDir, isDirectory: true, relativeTo: directory)
      .standardizedFileURL.resolvingSymlinksInPath()
    let destination = (output ?? root.appendingPathComponent(spec.name + ".xcworkspace"))
      .standardizedFileURL
    guard destination.pathExtension == "xcworkspace" else {
      throw ProjectError("Workspace output must be a .xcworkspace directory")
    }
    var keys = Set<String>()
    var sources = Set<String>()
    var projects: [GeneratedProject] = []
    for entry in spec.projects.sorted(by: { $0.key < $1.key }) {
      guard !entry.key.isEmpty, keys.insert(entry.key).inserted else {
        throw ProjectError("Empty or duplicate workspace project key: \(entry.key)")
      }
      guard let source = URL(string: entry.source), source.isFileURL,
        source.host == nil || source.host == "" || source.host == "localhost",
        source.query == nil, source.fragment == nil, source.pathExtension == "pkl"
      else {
        throw ProjectError("\(entry.key): project source must be a local file URI ending in .pkl")
      }
      let canonicalSource = source.standardizedFileURL.resolvingSymlinksInPath()
      guard sources.insert(canonicalSource.path).inserted else {
        throw ProjectError("Duplicate project module: \(source.path)")
      }
      do {
        try requirePath(canonicalSource, directory: false, at: "Project module")
        projects.append(
          try ProjectGenerator().compile(
            spec: entry.project, specDirectory: canonicalSource.deletingLastPathComponent()))
      } catch {
        throw ProjectError(
          "Workspace project '\(entry.key)' (\(source.path)):\n\(error.localizedDescription)")
      }
    }
    // Canonicalize existing symlinks before checking duplicates and nested bundles.
    let destinations = ([destination] + projects.map(\.destination)).map {
      $0.resolvingSymlinksInPath().standardizedFileURL.path
    }
    let uniqueDestinations = Set(destinations)
    guard uniqueDestinations.count == destinations.count else {
      throw ProjectError("Duplicate workspace/project output paths")
    }
    for path in destinations {
      var parent = URL(fileURLWithPath: path).deletingLastPathComponent()
      while parent.path != "/" {
        if uniqueDestinations.contains(parent.path) {
          throw ProjectError("Nested workspace/project output paths: \(parent.path) and \(path)")
        }
        parent.deleteLastPathComponent()
      }
    }
    let workspace = XMLElement(name: "Workspace")
    workspace.addAttribute(XMLNode.attribute(withName: "version", stringValue: "1.0") as! XMLNode)
    let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
    for project in projects {
      let reference = XMLElement(name: "FileRef")
      let path = relativePath(project.destination.resolvingSymlinksInPath(), from: parent)
      reference.addAttribute(
        XMLNode.attribute(withName: "location", stringValue: "group:" + path) as! XMLNode)
      workspace.addChild(reference)
    }
    let document = XMLDocument(rootElement: workspace)
    document.version = "1.0"
    document.characterEncoding = "UTF-8"
    var data = document.xmlData(options: [.nodePrettyPrint])
    data.append(0x0A)
    return GeneratedWorkspace(data: data, destination: destination, projects: projects)
  }
}
