import Foundation

/// A validated, in-memory result. Compiling a plan never writes output files.
public enum GenerationPlan: Sendable {
  case project(GeneratedProject)
  case workspace(GeneratedWorkspace)

  public static func compile(json: Data, specDirectory: URL, output: URL? = nil) throws -> Self {
    struct Header: Decodable { let kind: String? }
    let header = try JSONDecoder().decode(Header.self, from: json)
    switch header.kind {
    case nil:
      return .project(
        try ProjectGenerator().compile(json: json, specDirectory: specDirectory, output: output))
    case "workspace":
      return .workspace(
        try WorkspaceGenerator().compile(json: json, specDirectory: specDirectory, output: output))
    default: throw ProjectError("Unknown Pkl document kind: \(header.kind!)")
    }
  }

  public var destination: URL {
    switch self {
    case .project(let value): value.destination
    case .workspace(let value): value.destination
    }
  }
  public var projectCount: Int {
    switch self {
    case .project: 1
    case .workspace(let value): value.projects.count
    }
  }
  public var targetCount: Int {
    switch self {
    case .project(let value): value.targetCount
    case .workspace(let value): value.targetCount
    }
  }
  @discardableResult
  public func write() throws -> Bool {
    switch self {
    case .project(let value): try value.write()
    case .workspace(let value): try value.write()
    }
  }
}
