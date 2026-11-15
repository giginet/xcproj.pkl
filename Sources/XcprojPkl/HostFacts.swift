import Foundation

/// Only the host manifest is decoded here. Project and Target payloads stay opaque.
struct InputManifest: Decodable {
    let protocolVersion: Int
    let schemaVersion: Int
    let kind: ArtifactKind
    let rootArtifactId: String
    let paths: [PathRequest]
    let artifacts: [ArtifactRequest]
    let existingProjects: [ExistingProjectRequest]

    private enum CodingKeys: String, CodingKey {
        case protocolVersion, schemaVersion, kind, rootArtifactId, paths, artifacts,
            existingProjects
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        kind = try values.decode(ArtifactKind.self, forKey: .kind)
        rootArtifactId = try values.decode(String.self, forKey: .rootArtifactId)
        paths = try values.decode([PathRequest].self, forKey: .paths)
        artifacts = try values.decode([ArtifactRequest].self, forKey: .artifacts)
        existingProjects =
            try values.decodeIfPresent(
                [ExistingProjectRequest].self, forKey: .existingProjects) ?? []
    }

    func validate() throws {
        guard protocolVersion == 1, schemaVersion == 2 else {
            throw ProjectError(
                "Unsupported Pkl protocol or schemaVersion; expected schemaVersion 2")
        }
        guard !paths.isEmpty, Set(paths.map(\.id)).count == paths.count,
            paths.allSatisfy({ !$0.id.isEmpty }),
            !artifacts.isEmpty, Set(artifacts.map(\.id)).count == artifacts.count,
            let root = artifacts.first(where: { $0.id == rootArtifactId }), root.kind == kind
        else { throw ProjectError("Invalid or duplicate path/artifact identifiers in Snapshot") }
        let workspaceCount = artifacts.filter { $0.kind == .workspace }.count
        let projectCount = artifacts.filter { $0.kind == .project }.count
        guard kind != .scheme, workspaceCount == (kind == .workspace ? 1 : 0),
            kind != .project || (projectCount == 1 && existingProjects.isEmpty),
            projectCount + existingProjects.count > 0
        else { throw ProjectError("Invalid root artifact or Snapshot artifact set") }
        let pathIDs = Set(paths.map(\.id))
        for artifact in artifacts {
            guard pathIDs.contains(artifact.bundlePathId), pathIDs.contains(artifact.filePathId)
            else {
                throw ProjectError("Artifact \(artifact.id) refers to unknown paths")
            }
        }
        guard Set(existingProjects.map(\.key)).count == existingProjects.count,
            Set(existingProjects.map(\.bundlePathId)).count == existingProjects.count,
            existingProjects.allSatisfy({ !$0.key.isEmpty })
        else { throw ProjectError("Invalid or duplicate existing project identifiers in Snapshot") }
        for project in existingProjects {
            guard let request = paths.first(where: { $0.id == project.bundlePathId }),
                request.expectedKind == .directory, request.mustExist
            else {
                throw ProjectError(
                    "Existing project \(project.key) requires an existing directory path")
            }
        }
    }
}

struct ExistingProjectRequest: Decodable {
    let key: String
    let bundlePathId: String
}

enum ArtifactKind: String, Decodable, Sendable { case project, workspace, scheme }
struct ArtifactRequest: Decodable {
    let id: String
    let kind: ArtifactKind
    let bundlePathId: String
    let filePathId: String
}
struct PathRequest: Decodable {
    struct Base: Decodable {
        enum Kind: String, Decodable { case uri, request }
        enum Location: String, Decodable { case `self`, parent }
        let kind: Kind
        let uri: String?
        let id: String?
        let location: Location?
    }
    enum ExpectedKind: String, Decodable { case file, directory, any }
    let id: String
    let base: Base
    let path: String
    let expectedKind: ExpectedKind
    let mustExist: Bool
    let context: String
}

struct HostFacts: Encodable {
    struct PathFact: Encodable {
        let absolutePath: String
        let canonicalUri: String
        let components: [String]
        var url: URL { URL(fileURLWithPath: absolutePath) }
    }
    let protocolVersion = 1
    let paths: [String: PathFact]

    static func observe(_ manifest: InputManifest, outputDirectory: URL? = nil) throws -> HostFacts
    {
        try manifest.validate()
        let requests = Dictionary(uniqueKeysWithValues: manifest.paths.map { ($0.id, $0) })
        let root = manifest.artifacts.first { $0.id == manifest.rootArtifactId }!
        var facts: [String: PathFact] = [:]
        var visiting: [String] = []
        func resolve(_ id: String) throws -> PathFact {
            if let fact = facts[id] { return fact }
            guard let request = requests[id] else {
                throw ProjectError("Unknown path request: \(id)")
            }
            guard !visiting.contains(id) else {
                throw ProjectError(
                    "Path request cycle: \((visiting + [id]).joined(separator: " → "))")
            }
            visiting.append(id)
            defer { visiting.removeLast() }
            let base: URL
            switch request.base.kind {
            case .uri:
                guard let uri = request.base.uri, request.base.id == nil,
                    request.base.location == nil
                else { throw ProjectError("Invalid URI base: \(id)") }
                base = try localFileURL(uri)
            case .request:
                guard let parent = request.base.id, let location = request.base.location,
                    request.base.uri == nil
                else { throw ProjectError("Invalid request base: \(id)") }
                let parentURL = try resolve(parent).url
                base = location == .parent ? parentURL.deletingLastPathComponent() : parentURL
            }
            let resolved: URL
            if id == root.bundlePathId, let outputDirectory {
                resolved = outputDirectory.appendingPathComponent(request.path)
            } else if request.path.isEmpty {
                resolved = base
            } else {
                resolved = URL(
                    fileURLWithPath: request.path,
                    relativeTo: URL(fileURLWithPath: base.path, isDirectory: true))
            }
            let canonical = canonicalFileURL(resolved)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: canonical.path, isDirectory: &isDirectory)
            let actualKind = exists ? (isDirectory.boolValue ? "directory" : "file") : "missing"
            if request.mustExist && !exists {
                throw ProjectError(
                    "\(request.context): \(request.expectedKind.rawValue) does not exist: \(canonical.path)"
                )
            }
            if exists && request.expectedKind != .any && actualKind != request.expectedKind.rawValue
            {
                throw ProjectError(
                    "\(request.context): expected \(request.expectedKind.rawValue): \(canonical.path)"
                )
            }
            let fact = PathFact(
                absolutePath: canonical.path, canonicalUri: canonical.absoluteString,
                components: canonical.pathComponents)
            facts[id] = fact
            return fact
        }
        for request in manifest.paths { _ = try resolve(request.id) }
        return HostFacts(paths: facts)
    }
}

func localFileURL(_ value: String) throws -> URL {
    guard let url = URL(string: value), url.isFileURL,
        url.host == nil || url.host == "" || url.host == "localhost",
        url.query == nil, url.fragment == nil, url.path.hasPrefix("/")
    else { throw ProjectError("Expected a local file URI: \(value)") }
    return url
}

/// Foundation can leave symlink ancestors unresolved when the final path is missing.
/// Resolve the existing ancestor first, then append the missing components.
func canonicalFileURL(_ url: URL) -> URL {
    var ancestor = url.standardizedFileURL
    var suffix: [String] = []
    while ancestor.path != "/" && !FileManager.default.fileExists(atPath: ancestor.path) {
        suffix.append(ancestor.lastPathComponent)
        ancestor.deleteLastPathComponent()
    }
    var result = ancestor.resolvingSymlinksInPath()
    for component in suffix.reversed() { result.appendPathComponent(component) }
    return result.standardizedFileURL
}
