import Foundation

/// One tile inside a folder widget.
///
/// A tile is deliberately *not* an `LSApplicationProxy`. iOS gives third-party
/// apps no handle on another app, so a tile stores the only thing we are allowed
/// to act on: a URL to hand to the system, plus a cached name and icon to draw.
public struct FolderTile: Codable, Sendable, Hashable, Identifiable {
    /// What happens when the tile is tapped.
    public enum Kind: String, Codable, Sendable {
        /// A third-party app, opened through its URL scheme (`weixin://`).
        case app
        /// A website, normally handed to the user's chosen browser.
        case website
        /// A `shortcuts://run-shortcut?name=` invocation.
        case shortcut
        /// Anything else with a URL — a phone number, a mailto:, a file link.
        case custom
    }

    public var id: UUID
    public var kind: Kind
    /// Display name shown under the icon, already localized by the user.
    public var title: String
    /// The URL opened on tap. For third-party apps this is the app's scheme.
    public var urlString: String
    /// App Store id, used to fetch real icon artwork from the iTunes Search API.
    public var appStoreID: Int?
    /// `KnownApp.id` this tile came from, so a re-scan can refresh the scheme.
    public var catalogID: String?
    /// Overrides the artwork fetched via `appStoreID` — a user-chosen photo or symbol.
    public var customIconName: String?
    /// SF Symbol name, used when there is no artwork at all.
    public var symbolName: String?
    /// How the widget should ask the system to open this tile.
    ///
    /// Per tile rather than per folder because the answer depends on the target
    /// URL, not on the folder it sits in — see ``LaunchStrategy``. The default is
    /// ``LaunchStrategy/bounce`` because that is the only route that works for a
    /// custom scheme, and a custom scheme is what almost every app exposes.
    public var strategy: LaunchStrategy

    public init(
        id: UUID = UUID(),
        kind: Kind = .app,
        title: String,
        urlString: String,
        appStoreID: Int? = nil,
        catalogID: String? = nil,
        customIconName: String? = nil,
        symbolName: String? = nil,
        strategy: LaunchStrategy = .bounce
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.urlString = urlString
        self.appStoreID = appStoreID
        self.catalogID = catalogID
        self.customIconName = customIconName
        self.symbolName = symbolName
        self.strategy = strategy
    }

    /// The tile's target, or `nil` if the stored string is not a URL.
    public var url: URL? { URL(string: urlString) }

    public init(app: KnownApp, isInstalled: Bool = true) {
        self.init(
            kind: .app,
            title: app.name,
            urlString: app.scheme,
            appStoreID: app.appStoreID,
            catalogID: app.id
        )
    }
}

/// A group of tiles shown as one Home Screen widget — the "big folder".
public struct Folder: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// Ordered; the widget lays these out row-major.
    public var tiles: [FolderTile]
    /// Tint for the widget chrome, as `#RRGGBB`. Empty means "follow the system".
    public var colorHex: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        tiles: [FolderTile] = [],
        colorHex: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.tiles = tiles
        self.colorHex = colorHex
        self.updatedAt = updatedAt
    }
}

/// Everything the app persists and the widget reads.
public struct FolderLibrary: Codable, Sendable {
    /// Bumped when the on-disk shape changes, so old files can be migrated.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var folders: [Folder]
    /// Schemes that `canOpenURL` confirmed are installed, refreshed by the app.
    ///
    /// The widget cannot call `canOpenURL` (no `UIApplication` in an extension),
    /// so the app probes and leaves the answer here for the widget to read.
    public var installedSchemes: Set<String>
    public var lastProbeAt: Date?

    public init(
        schemaVersion: Int = FolderLibrary.currentSchemaVersion,
        folders: [Folder] = [],
        installedSchemes: Set<String> = [],
        lastProbeAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.installedSchemes = installedSchemes
        self.lastProbeAt = lastProbeAt
    }

    public static let empty = FolderLibrary()

    /// Whether a tile's target is known to be reachable on this device.
    ///
    /// Unknown schemes are treated as installed: a stale negative would hide a
    /// working tile, whereas a stale positive just fails at launch.
    public func isReachable(_ tile: FolderTile) -> Bool {
        guard lastProbeAt != nil else { return true }
        guard let scheme = tile.url?.scheme else { return false }
        return installedSchemes.contains(scheme)
    }
}
