import PklRuntimeResources

public enum ToolDefaults {
    /// Release packaging stamps the tag into the bundled Version.txt.
    public static let version = PklRuntimeResources.version
    public static let packageURI =
        "package://github.com/giginet/xcproj.pkl/releases/download/\(version)/xcproj@\(version)"
}
