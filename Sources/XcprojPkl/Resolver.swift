import CryptoKit
import Foundation

struct ResolvedTarget {
  let key: String
  let name: String
  let id: String
  let productId: String
  let spec: TargetSpec
  let settings: [String: SettingValue]

  var productExtension: String {
    switch spec.type! {
    case "application": "app"
    case "framework": "framework"
    case "bundle.unit-test": "xctest"
    case "bundle": "bundle"
    default: ""
    }
  }
  var productName: String { name + (productExtension.isEmpty ? "" : "." + productExtension) }
  var productFileType: String {
    switch spec.type! {
    case "application": "wrapper.application"
    case "framework": "wrapper.framework"
    case "bundle", "bundle.unit-test": "wrapper.cfbundle"
    default: "compiled.mach-o.executable"
    }
  }
}

struct ResolvedProject {
  let spec: ProjectSpec
  let root: URL
  let targets: [ResolvedTarget]
  let settings: [String: SettingValue]
}

struct Resolver {
  let project: ProjectSpec
  let specDirectory: URL

  func resolve() throws -> ResolvedProject {
    guard project.schemaVersion == 1 else {
      throw ProjectError("Unsupported schemaVersion: \(project.schemaVersion)")
    }
    try validateName(project.name, at: "name")
    guard !project.idNamespace.isEmpty else { throw ProjectError("idNamespace must not be empty") }
    guard !project.configs.isEmpty, project.configs[project.defaultConfiguration] != nil else {
      throw ProjectError("defaultConfiguration must name an entry in configs")
    }
    for (name, kind) in project.configs {
      try validateName(name, at: "configs")
      guard ["debug", "release"].contains(kind) else {
        throw ProjectError("configs.\(name): expected debug or release")
      }
    }
    let directory = URL(fileURLWithPath: specDirectory.path, isDirectory: true)
    let canonicalRoot = URL(
      fileURLWithPath: project.projectDir, isDirectory: true, relativeTo: directory
    )
    .standardizedFileURL.resolvingSymlinksInPath()
    let root = URL(fileURLWithPath: canonicalRoot.path, isDirectory: true)
    try requirePath(root, directory: true, at: "projectDir")
    guard !project.targets.isEmpty else {
      throw ProjectError("targets must contain at least one target")
    }
    // Validate even unused definitions, so broken reusable declarations cannot hide.
    for name in project.targetTemplates.keys.sorted() {
      let template = try resolveTemplate(name, stack: [])
      _ = try renderSettings(template.settings)
      try validateConfigFiles(template.configFiles, root: root, checkPaths: false)
    }
    for name in project.settingGroups.keys.sorted() {
      for config in [nil] + project.configs.keys.sorted().map(Optional.some) {
        _ = try resolveGroup(name, config: config, stack: [])
      }
    }
    try validateConfigFiles(project.configFiles, root: root)
    var targets: [ResolvedTarget] = []
    var names = Set<String>()
    var ids = Set<String>()
    for key in project.targets.keys.sorted() {
      let own = project.targets[key]!
      var target = TargetSpec()
      for template in own.templates {
        target = target.merging(try resolveTemplate(template, stack: []))
      }
      target = target.merging(own)
      // xcodeproj CLI's friendly alias differs from the on-disk product type.
      if target.type == "unit-test-bundle" { target.type = "bundle.unit-test" }
      let name = target.name ?? key
      try validateName(name, at: "targets.\(key).name")
      guard names.insert(name).inserted else {
        throw ProjectError("Duplicate target name: \(name)")
      }
      guard let type = target.type,
        ["application", "framework", "bundle", "bundle.unit-test", "tool"].contains(type)
      else {
        throw ProjectError("targets.\(key): missing or unsupported type")
      }
      guard let platform = target.platform, ["iOS", "macOS"].contains(platform) else {
        throw ProjectError("targets.\(key): missing or unsupported platform")
      }
      if type == "tool", platform != "macOS" {
        throw ProjectError("targets.\(key): tool requires macOS")
      }
      if let version = target.deploymentTarget,
        version.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) == nil
      {
        throw ProjectError("targets.\(key): invalid deploymentTarget '\(version)'")
      }
      var attributes = target.templateAttributes
      if attributes["target_name"] != nil {
        throw ProjectError("targets.\(key): target_name is reserved")
      }
      attributes["target_name"] = name
      let substitute: (String) throws -> String = {
        try expand($0, attributes: attributes, context: "targets.\(key)")
      }
      target.sources = try target.sources.map {
        var source = $0
        source.path = try substitute(source.path)
        source.excludes = try source.excludes.map(substitute)
        return source
      }
      target.dependencies = try target.dependencies.map {
        var dependency = $0
        dependency.target = try substitute(dependency.target)
        return dependency
      }
      target.configFiles = try target.configFiles.mapValues(substitute)
      try validateConfigFiles(target.configFiles, root: root)
      target.sources = try validateSources(target.sources, root: root, target: key)
      target.dependencies = try uniqueDependencies(target.dependencies, target: key)
      let id = target.id ?? stableID(namespace: project.idNamespace, kind: "target", key: key)
      let productId =
        target.productId ?? stableID(namespace: project.idNamespace, kind: "product", key: key)
      for value in [id, productId] {
        guard value.range(of: #"^[A-Fa-f0-9]{24}$"#, options: .regularExpression) != nil else {
          throw ProjectError("targets.\(key): ID must contain 24 hexadecimal characters")
        }
        guard ids.insert(value.uppercased()).inserted else {
          throw ProjectError("Duplicate object ID: \(value)")
        }
      }
      var settings = defaults(for: target, name: name)
      let overrides = try renderSettings(target.settings).mapValues { try $0.map(substitute) }
      // An explicit base value also overrides lower-priority per-config presets.
      for key in overrides.keys where !key.contains("[config=") {
        for preset in Array(settings.keys) where preset.hasPrefix(key + "[config=") {
          settings.removeValue(forKey: preset)
        }
      }
      settings.merge(overrides) { _, new in new }
      targets.append(
        ResolvedTarget(
          key: key, name: name, id: id, productId: productId, spec: target, settings: settings))
    }
    let byKey = Dictionary(uniqueKeysWithValues: targets.map { ($0.key, $0) })
    for target in targets {
      for dependency in target.spec.dependencies {
        guard let destination = byKey[dependency.target] else {
          throw ProjectError("targets.\(target.key): unknown dependency '\(dependency.target)'")
        }
        if target.spec.platform != destination.spec.platform {
          throw ProjectError(
            "targets.\(target.key): dependency '\(dependency.target)' has a different platform")
        }
        if dependency.link && destination.spec.type != "framework" {
          throw ProjectError(
            "targets.\(target.key): only frameworks can be linked; use link = false for '\(dependency.target)'"
          )
        }
        if dependency.embed
          && (destination.spec.type != "framework" || target.spec.type != "application")
        {
          throw ProjectError(
            "targets.\(target.key): embedding is supported for application → framework dependencies only"
          )
        }
      }
    }
    try validateAcyclicGraph(
      Dictionary(
        uniqueKeysWithValues: targets.map { ($0.key, $0.spec.dependencies.map(\.target)) }),
      label: "Target dependency")
    var settings: [String: SettingValue] = ["ALWAYS_SEARCH_USER_PATHS": .string("NO")]
    settings.merge(try renderSettings(project.settings)) { _, new in new }
    return ResolvedProject(spec: project, root: root, targets: targets, settings: settings)
  }

  private func resolveTemplate(_ name: String, stack: [String]) throws -> TargetSpec {
    if stack.contains(name) {
      throw ProjectError("Target template cycle: \((stack + [name]).joined(separator: " → "))")
    }
    guard let own = project.targetTemplates[name] else {
      throw ProjectError("Unknown target template: \(name)")
    }
    var result = TargetSpec()
    for parent in own.templates {
      result = result.merging(try resolveTemplate(parent, stack: stack + [name]))
    }
    return result.merging(own)
  }

  private func resolveGroup(_ name: String, config: String?, stack: [String]) throws -> [String:
    SettingValue]
  {
    if stack.contains(name) {
      throw ProjectError("Setting group cycle: \((stack + [name]).joined(separator: " → "))")
    }
    guard let settings = project.settingGroups[name] else {
      throw ProjectError("Unknown setting group: \(name)")
    }
    return try evaluate(settings, config: config, stack: stack + [name])
  }

  private func evaluate(_ settings: Settings, config: String?, stack: [String]) throws -> [String:
    SettingValue]
  {
    for (name, value) in settings.configs {
      guard project.configs[name] != nil else {
        throw ProjectError("Unknown build configuration in settings: \(name)")
      }
      guard value.configs.isEmpty else {
        throw ProjectError("settings.configs.\(name): nested configs are not supported")
      }
    }
    var values: [String: SettingValue] = [:]
    for group in settings.groups {
      values.merge(try resolveGroup(group, config: config, stack: stack)) { _, new in new }
    }
    for key in settings.base.keys {
      if key.isEmpty || key.contains("[config=") {
        throw ProjectError(
          "Invalid build setting '\(key)'; use settings.configs for configuration conditions")
      }
    }
    values.merge(settings.base) { _, new in new }
    if let config, let overrides = settings.configs[config] {
      values.merge(try evaluate(overrides, config: config, stack: stack)) { _, new in new }
    }
    return values
  }

  private func renderSettings(_ settings: Settings) throws -> [String: SettingValue] {
    let base = try evaluate(settings, config: nil, stack: [])
    var result = base
    for config in project.configs.keys.sorted() {
      for (key, value) in try evaluate(settings, config: config, stack: []) where base[key] != value
      {
        result["\(key)[config=\(config)]"] = value
      }
    }
    return result
  }

  private func defaults(for target: TargetSpec, name: String) -> [String: SettingValue] {
    let macOS = target.platform == "macOS"
    var result: [String: SettingValue] = [
      "PRODUCT_NAME": .string("$(TARGET_NAME)"),
      "SWIFT_VERSION": .string("6.0"),
      "SDKROOT": .string(macOS ? "macosx" : "iphoneos"),
      "SUPPORTED_PLATFORMS": .array(macOS ? ["macosx"] : ["iphoneos", "iphonesimulator"]),
    ]
    if let version = target.deploymentTarget {
      result[macOS ? "MACOSX_DEPLOYMENT_TARGET" : "IPHONEOS_DEPLOYMENT_TARGET"] = .string(version)
    }
    for (config, kind) in project.configs {
      result["SWIFT_OPTIMIZATION_LEVEL[config=\(config)]"] = .string(
        kind == "debug" ? "-Onone" : "-O")
    }
    if !macOS { result["TARGETED_DEVICE_FAMILY"] = .string("1,2") }
    if target.type != "tool" {
      result["GENERATE_INFOPLIST_FILE"] = .string("YES")
      let suffix = name.replacingOccurrences(
        of: #"[^A-Za-z0-9.-]"#, with: "-", options: .regularExpression)
      result["PRODUCT_BUNDLE_IDENTIFIER"] = .string("\(project.idNamespace).\(suffix)")
    }
    if target.type == "framework" {
      result["DEFINES_MODULE"] = .string("YES")
      result["SKIP_INSTALL"] = .string("YES")
      result["DYLIB_INSTALL_NAME_BASE"] = .string("@rpath")
    }
    if target.type == "application" {
      result["LD_RUNPATH_SEARCH_PATHS"] = .array([
        "$(inherited)", macOS ? "@executable_path/../Frameworks" : "@executable_path/Frameworks",
      ])
    }
    return result
  }

  private func validateConfigFiles(_ files: [String: String], root: URL, checkPaths: Bool = true)
    throws
  {
    for (config, path) in files {
      guard project.configs[config] != nil else {
        throw ProjectError("configFiles: unknown configuration '\(config)'")
      }
      if checkPaths {
        try requirePath(
          URL(fileURLWithPath: path, relativeTo: root), directory: false,
          at: "configFiles.\(config)")
      }
    }
  }
}

func stableID(namespace: String, kind: String, key: String) -> String {
  SHA256.hash(data: Data("\(namespace)\0\(kind)\0\(key)".utf8)).prefix(12).map {
    String(format: "%02X", $0)
  }.joined()
}

func validateName(_ name: String, at context: String) throws {
  guard name.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_. -]*$"#, options: .regularExpression) != nil
  else {
    throw ProjectError(
      "\(context): '\(name)' must use letters, digits, spaces, periods, underscores, or hyphens")
  }
}

func requirePath(_ url: URL, directory: Bool, at context: String) throws {
  var isDirectory: ObjCBool = false
  guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
    isDirectory.boolValue == directory
  else {
    throw ProjectError(
      "\(context): \(directory ? "directory" : "file") does not exist: \(url.path)")
  }
}

func expand(_ string: String, attributes: [String: String], context: String) throws -> String {
  let regex = try NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
  var result = string
  for match in regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
    .reversed()
  {
    let key = String(string[Range(match.range(at: 1), in: string)!])
    guard let replacement = attributes[key] else {
      throw ProjectError("\(context): unknown template attribute '${\(key)}'")
    }
    result.replaceSubrange(Range(match.range, in: result)!, with: replacement)
  }
  return result
}

private func uniqueDependencies(_ dependencies: [Dependency], target: String) throws -> [Dependency]
{
  var result: [Dependency] = []
  for dependency in dependencies {
    if let previous = result.first(where: { $0.target == dependency.target }) {
      guard previous == dependency else {
        throw ProjectError(
          "targets.\(target): conflicting dependency options for '\(dependency.target)'")
      }
    } else {
      result.append(dependency)
    }
  }
  return result
}

private func validateSources(_ sources: [Source], root: URL, target: String) throws -> [Source] {
  var result: [Source] = []
  var paths: [String] = []
  for var source in sources {
    guard ["folder", "file"].contains(source.kind) else {
      throw ProjectError("targets.\(target): unsupported source kind '\(source.kind)'")
    }
    let url = URL(fileURLWithPath: source.path, relativeTo: root).standardizedFileURL
      .resolvingSymlinksInPath()
    try requirePath(url, directory: source.kind == "folder", at: "targets.\(target).sources")
    if source.kind == "file", !source.excludes.isEmpty {
      throw ProjectError("excludes requires a folder source")
    }
    for exclusion in source.excludes {
      guard !exclusion.isEmpty, !exclusion.hasPrefix("/"),
        !exclusion.split(separator: "/").contains(".."),
        !exclusion.contains("*"), !exclusion.contains("?")
      else {
        throw ProjectError("Invalid folder exclusion '\(exclusion)': use an exact relative path")
      }
      guard FileManager.default.fileExists(atPath: url.appendingPathComponent(exclusion).path)
      else {
        throw ProjectError("Excluded path does not exist: \(source.path)/\(exclusion)")
      }
    }
    if let index = paths.firstIndex(of: url.path) {
      guard result[index].kind == source.kind else {
        throw ProjectError("Conflicting source kinds for \(source.path)")
      }
      result[index].excludes = Array(Set(result[index].excludes + source.excludes)).sorted()
    } else {
      for path in paths where url.path.hasPrefix(path + "/") || path.hasPrefix(url.path + "/") {
        throw ProjectError(
          "targets.\(target): overlapping source roots '\(path)' and '\(url.path)'")
      }
      source.excludes = Array(Set(source.excludes)).sorted()
      result.append(source)
      paths.append(url.path)
    }
  }
  return result
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
