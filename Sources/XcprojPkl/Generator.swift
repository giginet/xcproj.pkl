import Foundation
import XcodeProjectFormat

public struct GeneratedProject: Sendable {
  public let data: Data
  public let destination: URL
  public let targetCount: Int

  /// Only project.xcproj is replaced. Schemes and other bundle contents are preserved.
  @discardableResult
  public func write() throws -> Bool {
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.appendingPathComponent("project.pbxproj").path) {
      throw ProjectError(
        "Refusing to overwrite a legacy project containing project.pbxproj: \(destination.path)")
    }
    let file = destination.appendingPathComponent("project.xcproj")
    if let existing = try? Data(contentsOf: file), existing == data { return false }
    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
    try data.write(to: file, options: .atomic)
    return true
  }
}

public struct ProjectGenerator: Sendable {
  public init() {}

  public func compile(json: Data, specDirectory: URL, output: URL? = nil) throws -> GeneratedProject
  {
    let spec = try JSONDecoder().decode(ProjectSpec.self, from: json)
    let resolved = try Resolver(project: spec, specDirectory: specDirectory).resolve()
    let destination = (output ?? resolved.root.appendingPathComponent(spec.name + ".xcodeproj"))
      .standardizedFileURL
    guard destination.pathExtension == "xcodeproj" else {
      throw ProjectError("Output must be a .xcodeproj directory")
    }
    let wire = try render(
      resolved, outputParent: destination.deletingLastPathComponent().resolvingSymlinksInPath())
    let input = try JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys])
    let schema = try XCSchema.Project(jsonRepresentation: input)
    try ProjectValidator.validate(schema)
    return GeneratedProject(
      data: try schema.jsonRepresentation(), destination: destination,
      targetCount: resolved.targets.count)
  }

  private func render(_ project: ResolvedProject, outputParent: URL) throws -> [String: Any] {
    let targets = project.targets
    let byKey = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0) })
    func fileURL(_ path: String) -> URL {
      URL(fileURLWithPath: path, relativeTo: project.root).standardizedFileURL
        .resolvingSymlinksInPath()
    }
    func encodedPath(_ url: URL) throws -> String {
      try XCSchema.FilePath(base: .project, path: relativePath(url, from: outputParent))
        .stringRepresentation
    }
    var files: [[String: Any]] = []
    var sourceOwners: [String: [(ResolvedTarget, Source)]] = [:]
    for target in targets {
      for source in target.spec.sources {
        sourceOwners[fileURL(source.path).path, default: []].append((target, source))
      }
    }
    for path in sourceOwners.keys.sorted() {
      let owners = sourceOwners[path]!
      let kind = owners[0].1.kind
      guard owners.allSatisfy({ $0.1.kind == kind }) else {
        throw ProjectError("Conflicting source kinds for \(path)")
      }
      var file: [String: Any] = ["path": try encodedPath(URL(fileURLWithPath: path))]
      if kind == "folder" {
        file["kind"] = "folder"
        file["target-membership"] = owners.map { $0.0.name }
        file["membership-exceptions"] = owners.compactMap { target, source -> [String: Any]? in
          source.excludes.isEmpty ? nil : ["target": target.name, "exclusions": source.excludes]
        }
      } else {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let phase =
          ["swift", "m", "mm", "c", "cc", "cpp", "cxx"].contains(ext)
          ? "compile-sources"
          : ["h", "hpp"].contains(ext) ? "headers" : "resources"
        file["target-membership"] = owners.map { "\($0.0.name)/\(phase)" }
      }
      files.append(file)
    }
    // xcconfig references use stable IDs, avoiding ambiguous equal basenames.
    let configPaths = Set(
      Array(project.spec.configFiles.values) + targets.flatMap { Array($0.spec.configFiles.values) }
    )
    var configIDs: [String: String] = [:]
    var configReferences: [[String: Any]] = []
    for path in configPaths.sorted() {
      let url = fileURL(path)
      let stablePath = relativePath(url, from: project.root)
      let id = stableID(namespace: project.spec.idNamespace, kind: "xcconfig", key: stablePath)
      configIDs[path] = id
      if !configReferences.contains(where: { $0["id"] as? String == id }) {
        configReferences.append(["path": try encodedPath(url), "id": id])
      }
    }
    if !configReferences.isEmpty {
      files.append(["kind": "group", "name": "Configurations", "children": configReferences])
    }
    func configurations(_ paths: [String: String], specialized: Bool) -> [Any] {
      project.spec.configs.keys.sorted().compactMap { name -> Any? in
        if let path = paths[name] { return ["name": name, "file": "id:" + configIDs[path]!] }
        return specialized ? nil : name
      }
    }
    var products: [[String: Any]] = []
    for target in targets {
      var memberships: [Any] = []
      for consumer in targets {
        for dependency in consumer.spec.dependencies where dependency.target == target.key {
          if dependency.link { memberships.append("\(consumer.name)/frameworks") }
          if dependency.embed {
            memberships.append(
              [
                "build-phase": "\(consumer.name)/copy/Embed Frameworks",
                "code-sign-on-copy": true,
                "header-preservation": "remove-on-copy",
              ] as [String: Any])
          }
        }
      }
      products.append([
        "path": "<PRODUCTS>/" + target.productName,
        "id": target.productId,
        "type": target.productFileType,
        "index": false,
        "target-membership": memberships,
      ])
    }
    files.append(["kind": "group", "name": "Products", "children": products])
    let targetObjects: [[String: Any]] = targets.map { target in
      var phases: [Any] = ["headers", "compile-sources", "frameworks", "resources"]
      if target.spec.dependencies.contains(where: \.embed) {
        phases.append([
          "kind": "copy", "name": "Embed Frameworks", "bundle-base-path": "frameworks-directory",
        ])
      }
      return [
        "name": target.name,
        "id": target.id,
        "product": "Products/" + target.productName,
        "product-type": target.spec.type!,
        "build-phases": phases,
        "build-settings": target.settings.mapValues(\.jsonValue),
        "dependencies": target.spec.dependencies.map { byKey[$0.target]!.name },
        "specialized-configurations": configurations(target.spec.configFiles, specialized: true),
      ]
    }
    return [
      "default-configuration": project.spec.defaultConfiguration,
      "configurations": configurations(project.spec.configFiles, specialized: false),
      "localizations": ["development": "en", "supported": ["Base"]],
      "files": files,
      "targets": targetObjects,
      "build-settings": project.settings.mapValues(\.jsonValue),
    ]
  }
}

func relativePath(_ destination: URL, from base: URL) -> String {
  let target = destination.standardizedFileURL.pathComponents
  let origin = base.standardizedFileURL.pathComponents
  let common = zip(target, origin).prefix { $0 == $1 }.count
  let components = Array(repeating: "..", count: origin.count - common) + target.dropFirst(common)
  return components.isEmpty ? "." : components.joined(separator: "/")
}
