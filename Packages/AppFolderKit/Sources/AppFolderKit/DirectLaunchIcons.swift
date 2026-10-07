import Foundation

/// Artwork for a direct-launch slot, fetched and cached where the widget can read it.
///
/// ## Why this exists
///
/// A direct-launch tile hands the system a `SystemShortcut`, and the system hands
/// back exactly one thing: a display name. It does **not** hand back the app's
/// icon — `SystemShortcut`'s `displayRepresentation.image` has no public getter,
/// and nothing in SwiftUI or WidgetKit can render one anyway. So a tile that can
/// open any app has no artwork, and a launcher of blank tiles is not what anyone
/// wants.
///
/// The name is enough to get the artwork back: the App Store's public lookup
/// endpoint answers a name with the app's icon. That costs one round trip per
/// newly seen name, and the result is cached on disk in the App Group, so the
/// widget's synchronous render always has something to draw — the rule the
/// widget's own icon cache is built on.
///
/// ## Why not `IconStore`
///
/// ``IconStore`` in the app target does the same dance but returns `UIImage`,
/// which this package cannot import, and it resolves *tiles* by App Store id.
/// Here the input is a name, and the caller may be the widget extension, which
/// the app target's type cannot reach. So the fetch lives here, on `Data`, for
/// both processes to share.
public enum DirectLaunchIcons {
    /// Where artwork lives inside the App Group, same directory ``IconStore`` uses
    /// so the two never write two copies of the same icon under two names.
    public static let directoryName = "Icons"

    /// The icon for a slot, from disk if it is there and the network if it is not.
    ///
    /// - Parameter appStoreID: the resolved id, when the app already knows it. A
    ///   hit here is a plain file read with no request at all.
    /// - Parameter name: the system's display name, used to look the app up when
    ///   there is no id.
    /// - Returns: the PNG bytes, or `nil` when the app cannot be found.
    public static func iconData(appStoreID: Int?, name: String) async -> Data? {
        let directory = containerDirectory()

        if let id = appStoreID ?? AppCatalog.match(name: name)?.appStoreID,
           let cached = read(directory: directory, id: id) {
            return cached
        }

        // One storefront attempt per resolved id, not the full region sweep
        // ``IconStore`` runs: that sweep exists for apps bought in another region
        // whose id the device cannot resolve at all, which is a case a slot the
        // *user* just picked does not have — the app is on this device, so the
        // device's own store has it.
        guard let id = appStoreID ?? AppCatalog.match(name: name)?.appStoreID,
              let data = await fetch(appStoreID: id)
        else { return nil }

        write(directory: directory, id: id, data: data)
        return data
    }

    /// The file name an icon is cached under, mirroring ``IconStore``'s scheme so
    /// the two stores agree on where a given app's artwork lives.
    public static func fileName(appStoreID: Int) -> String { "\(appStoreID).png" }

    // MARK: - Disk

    /// The App Group's icon directory, created if it is missing.
    ///
    /// Public so a caller can tell "no container" apart from "no icon" — the same
    /// distinction ``IconStore/isCacheSharedWithWidget`` exists to make, and the
    /// one that decides whether a widget will find what a preview found.
    public static func containerDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        ) else { return nil }
        let directory = container.appending(path: directoryName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func read(directory: URL?, id: Int) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appending(path: fileName(appStoreID: id)))
    }

    private static func write(directory: URL?, id: Int, data: Data) {
        guard let directory else { return }
        try? data.write(to: directory.appending(path: fileName(appStoreID: id)), options: .atomic)
    }

    // MARK: - Network

    /// The artwork for one id, one request.
    ///
    /// No `country` parameter, so the request resolves to the device's own
    /// storefront — the right first try for an app that is installed here, and the
    /// reason the full ``AppStoreRegions/lookupOrder`` sweep is not needed.
    static func fetch(appStoreID id: Int) async -> Data? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [URLQueryItem(name: "id", value: String(id))]
        guard let url = components?.url else { return nil }

        guard let (payload, _) = try? await URLSession.shared.data(from: url),
              let first = AppStoreLookup.parse(payload).first,
              let artworkURL = first.artworkURL.flatMap(URL.init(string:))
        else { return nil }

        return try? await URLSession.shared.data(from: artworkURL).0
    }
}