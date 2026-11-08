import Foundation

/// Where the app keeps its files and finds the now-playing helper bundled inside it.
struct AppPaths {
    private static let supportFolderName = "KTV Lyrics"
    private static let adapterScriptName = "mediaremote-adapter.pl"
    private static let adapterFrameworkName = "MediaRemoteAdapter.framework"

    let cacheDirectory: URL
    let overridesDirectory: URL
    /// Nil when the app is not running from a bundle that contains the helper.
    let adapterScript: URL?
    let adapterFramework: URL?

    /// Absolute paths only: the adapter fails when given relative ones.
    static func current(
        fileManager: FileManager = .default,
        resources: URL? = Bundle.main.resourceURL
    ) -> AppPaths {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let root = support.appendingPathComponent(supportFolderName, isDirectory: true)
        return AppPaths(
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            overridesDirectory: root.appendingPathComponent("overrides", isDirectory: true),
            adapterScript: resources?.appendingPathComponent(adapterScriptName).absoluteURL,
            adapterFramework: resources?.appendingPathComponent(adapterFrameworkName).absoluteURL
        )
    }
}
