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

    /// The app's universal link, when it has one and the route above is
    /// ``LaunchStrategy/universalLink``.
    ///
    /// Stored on the tile rather than looked up from ``catalogID`` at render
    /// time, for two reasons. The widget would otherwise have to search the
    /// catalogue on every draw, and — more importantly — a tile and the catalogue
    /// entry it came from can disagree. The user may have edited the URL, the
    /// tile may have been created before the catalogue learned the link, or the
    /// app may have been removed from the catalogue entirely. What is on the tile
    /// is what gets opened; that is the property worth preserving.
    ///
    /// Kept separate from ``urlString`` for the same reason ``LaunchStrategy``
    /// exists: the two routes need different URLs, and one tile carries both so
    /// switching routes in the editor does not destroy the other one.
    public var universalLinkString: String?

    public init(
        id: UUID = UUID(),
        kind: Kind = .app,
        title: String,
        urlString: String,
        appStoreID: Int? = nil,
        catalogID: String? = nil,
        customIconName: String? = nil,
        symbolName: String? = nil,
        strategy: LaunchStrategy = .bounce,
        universalLinkString: String? = nil
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
        self.universalLinkString = universalLinkString
    }

    /// The tile's target, or `nil` if the stored string is not a URL.
    public var url: URL? { URL(string: urlString) }

    /// The app's universal link, or `nil` if it has none.
    public var universalLink: URL? { universalLinkString.flatMap(URL.init(string:)) }

    /// The URL the widget will actually hand to the system.
    ///
    /// One place decides, so the widget cannot draw a button that opens something
    /// other than what the editor showed. Note what happens when a
    /// ``LaunchStrategy/universalLink`` tile has no link: the answer is `nil`, not
    /// the scheme. Falling back to ``url`` would be the easy thing to write and
    /// the wrong thing to ship — `OpenURLIntent` ignores custom schemes, so the
    /// tile would look live and do nothing, which is the exact bug this whole
    /// type exists to prevent.
    public var launchURL: URL? {
        switch strategy {
        case .universalLink: universalLink
        case .bounce, .systemShortcut: url
        }
    }

    /// Whether tapping this tile can reach its target at all.
    ///
    /// False for the one configuration that cannot work — "直接打开" on an app
    /// with no universal link — so the widget's silence is a decision the app
    /// made rather than a mystery the user has to debug by tapping.
    public var canLaunch: Bool {
        switch strategy {
        case .universalLink: universalLink != nil
        case .bounce: url != nil
        case .systemShortcut: false
        }
    }

    /// A tile for a catalogue entry, carrying both routes the entry offers.
    ///
    /// The link is a property of the app, not of the route, so it survives the
    /// user switching between 直接打开 and 中转. Dropping it when the route
    /// changes would make a tile lose its artwork as a side effect of a setting
    /// the user thinks of as unrelated.
    public init(app: KnownApp) {
        self.init(
            kind: .app,
            title: app.name,
            urlString: app.scheme,
            appStoreID: app.appStoreID,
            catalogID: app.id,
            universalLinkString: app.universalLink
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
    /// Schemes the app asked the system about and got a yes for.
    ///
    /// The widget cannot call `canOpenURL` — there is no `UIApplication` in an
    /// extension — so the app probes and leaves the answers here.
    public var installedSchemes: Set<String>
    /// Every scheme the app asked about, regardless of the answer.
    ///
    /// This is what makes ``isReachable(_:)`` honest. Without it, "not in
    /// `installedSchemes`" would conflate two very different things: *we asked
    /// and the app isn't there* versus *we never asked*. Only the first is a
    /// reason to hide a tile, and only a few dozen schemes can ever be asked
    /// about — see ``AppCatalog/queryBudget``.
    public var probedSchemes: Set<String>
    public var lastProbeAt: Date?

    public init(
        schemaVersion: Int = FolderLibrary.currentSchemaVersion,
        folders: [Folder] = [],
        installedSchemes: Set<String> = [],
        probedSchemes: Set<String> = [],
        lastProbeAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.installedSchemes = installedSchemes
        self.probedSchemes = probedSchemes
        self.lastProbeAt = lastProbeAt
    }

    /// Decodes leniently so a field added in a later version doesn't discard the
    /// user's folders. Synthesized `Codable` ignores property defaults when a key
    /// is absent, which would make every schema addition a data loss event.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? FolderLibrary.currentSchemaVersion
        folders = try container.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        installedSchemes = try container.decodeIfPresent(Set<String>.self, forKey: .installedSchemes) ?? []
        probedSchemes = try container.decodeIfPresent(Set<String>.self, forKey: .probedSchemes) ?? []
        lastProbeAt = try container.decodeIfPresent(Date.self, forKey: .lastProbeAt)
    }

    public static let empty = FolderLibrary()

    /// Whether a tile's target is known to be reachable on this device.
    ///
    /// Conservative in one direction only: a scheme we never asked about is
    /// treated as reachable, because hiding a working tile is worse than showing
    /// one that fails. Only a scheme we positively asked about and got a no for
    /// is considered unreachable.
    public func isReachable(_ tile: FolderTile) -> Bool {
        guard let scheme = tile.url?.scheme?.lowercased() else { return false }
        guard probedSchemes.contains(scheme) else { return true }
        return installedSchemes.contains(scheme)
    }
}
