import Foundation

public enum SettingValue: Codable, Equatable, Sendable {
  case string(String)
  case array([String])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else {
      self = .array(try container.decode([String].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    }
  }

  var jsonValue: Any {
    switch self {
    case .string(let value): value
    case .array(let value): value
    }
  }

  func map(_ transform: (String) throws -> String) rethrows -> Self {
    switch self {
    case .string(let value): return .string(try transform(value))
    case .array(let value): return .array(try value.map(transform))
    }
  }
}

struct Settings: Decodable, Sendable {
  var groups: [String] = []
  var base: [String: SettingValue] = [:]
  var configs: [String: Settings] = [:]

  init() {}
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
    base = try c.decodeIfPresent([String: SettingValue].self, forKey: .base) ?? [:]
    configs = try c.decodeIfPresent([String: Settings].self, forKey: .configs) ?? [:]
  }
  enum CodingKeys: String, CodingKey, CaseIterable { case groups, base, configs }

  func merging(_ other: Self) -> Self {
    var result = self
    result.groups += other.groups
    result.base.merge(other.base) { _, new in new }
    result.configs.merge(other.configs) { old, new in old.merging(new) }
    return result
  }
}

struct Source: Decodable, Equatable, Sendable {
  var path: String
  var kind: String = "folder"
  var excludes: [String] = []
  enum CodingKeys: String, CodingKey, CaseIterable { case path, kind, excludes }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    path = try c.decode(String.self, forKey: .path)
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "folder"
    excludes = try c.decodeIfPresent([String].self, forKey: .excludes) ?? []
  }
}

struct Dependency: Decodable, Equatable, Sendable {
  var target: String
  var link: Bool = true
  var embed: Bool = false
  enum CodingKeys: String, CodingKey, CaseIterable { case target, link, embed }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    target = try c.decode(String.self, forKey: .target)
    link = try c.decodeIfPresent(Bool.self, forKey: .link) ?? true
    embed = try c.decodeIfPresent(Bool.self, forKey: .embed) ?? false
  }
}

struct TargetSpec: Decodable, Sendable {
  var name: String?
  var templates: [String] = []
  var templateAttributes: [String: String] = [:]
  var type: String?
  var platform: String?
  var deploymentTarget: String?
  var id: String?
  var productId: String?
  var settings = Settings()
  var configFiles: [String: String] = [:]
  var sources: [Source] = []
  var dependencies: [Dependency] = []

  init() {}
  enum CodingKeys: String, CodingKey, CaseIterable {
    case name, templates, templateAttributes, type, platform, deploymentTarget
    case id, productId, settings, configFiles, sources, dependencies
  }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    templates = try c.decodeIfPresent([String].self, forKey: .templates) ?? []
    templateAttributes =
      try c.decodeIfPresent([String: String].self, forKey: .templateAttributes) ?? [:]
    type = try c.decodeIfPresent(String.self, forKey: .type)
    platform = try c.decodeIfPresent(String.self, forKey: .platform)
    deploymentTarget = try c.decodeIfPresent(String.self, forKey: .deploymentTarget)
    id = try c.decodeIfPresent(String.self, forKey: .id)
    productId = try c.decodeIfPresent(String.self, forKey: .productId)
    settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    configFiles = try c.decodeIfPresent([String: String].self, forKey: .configFiles) ?? [:]
    sources = try c.decodeIfPresent([Source].self, forKey: .sources) ?? []
    dependencies = try c.decodeIfPresent([Dependency].self, forKey: .dependencies) ?? []
  }

  func merging(_ other: Self) -> Self {
    var result = self
    result.name = other.name ?? name
    result.type = other.type ?? type
    result.platform = other.platform ?? platform
    result.deploymentTarget = other.deploymentTarget ?? deploymentTarget
    result.id = other.id ?? id
    result.productId = other.productId ?? productId
    result.templateAttributes.merge(other.templateAttributes) { _, new in new }
    result.settings = settings.merging(other.settings)
    result.configFiles.merge(other.configFiles) { _, new in new }
    result.sources += other.sources
    result.dependencies += other.dependencies
    return result
  }
}

struct ProjectSpec: Decodable, Sendable {
  let schemaVersion: Int
  let name: String
  let idNamespace: String
  let projectDir: String
  let configs: [String: String]
  let defaultConfiguration: String
  let settings: Settings
  let configFiles: [String: String]
  let settingGroups: [String: Settings]
  let targetTemplates: [String: TargetSpec]
  let targets: [String: TargetSpec]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, name, idNamespace, projectDir, configs, defaultConfiguration
    case settings, configFiles, settingGroups, targetTemplates, targets
  }
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try c.rejectUnknownKeys(in: decoder, allowed: CodingKeys.allCases)
    schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
    name = try c.decode(String.self, forKey: .name)
    idNamespace = try c.decodeIfPresent(String.self, forKey: .idNamespace) ?? name
    projectDir = try c.decodeIfPresent(String.self, forKey: .projectDir) ?? "."
    configs =
      try c.decodeIfPresent([String: String].self, forKey: .configs) ?? [
        "Debug": "debug", "Release": "release",
      ]
    defaultConfiguration =
      try c.decodeIfPresent(String.self, forKey: .defaultConfiguration) ?? "Debug"
    settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    configFiles = try c.decodeIfPresent([String: String].self, forKey: .configFiles) ?? [:]
    settingGroups = try c.decodeIfPresent([String: Settings].self, forKey: .settingGroups) ?? [:]
    targetTemplates =
      try c.decodeIfPresent([String: TargetSpec].self, forKey: .targetTemplates) ?? [:]
    targets = try c.decode([String: TargetSpec].self, forKey: .targets)
  }
}

private struct AnyKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer {
  fileprivate func rejectUnknownKeys(in decoder: any Decoder, allowed: [Key]) throws {
    let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
    let unknown = Set(keys).subtracting(allowed.map(\.stringValue)).sorted()
    if !unknown.isEmpty {
      let path = decoder.codingPath.map(\.stringValue).joined(separator: ".")
      throw ProjectError(
        "\(path.isEmpty ? "project" : path): unknown fields: \(unknown.joined(separator: ", "))")
    }
  }
}
