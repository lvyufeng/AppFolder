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
    /// No longer what decides — ``launchRoute`` derives the route from the tile's
    /// own URLs, and the widget reads *that*. It survives because it is written
    /// on disk and a library may be read by a build from before the derivation
    /// existed, and because ``launchRoute`` still falls back to it for a tile
    /// that carries no URL at all. ``LibraryRepair`` keeps it in step with the
    /// derived answer on every load, so the two do not drift.
    ///
    /// It stays `var` and stays persisted rather than being deleted: removing a
    /// key is what makes an old build's decode fail, and a failed decode is the
    /// user losing every folder — see ``Folder/init(from:)`` on that bargain.
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
    ///
    /// Shape is checked here rather than at the point of use, because this is the
    /// single door both the editor and the widget come through. ``OpenLinkIntent``
    /// reaches an app through an `https://` universal link and nothing else — a
    /// link that is really a custom scheme makes it *throw*, and a throw from a
    /// `Button(intent:)` on the Home Screen is a tile that draws normally and does
    /// nothing when tapped. That is the 地图 bug, and refusing a malformed link
    /// here is what keeps it from coming back in through the link instead of
    /// through the route picker.
    public var universalLink: URL? {
        guard let url = universalLinkString.flatMap(URL.init(string:)) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    /// The URL the widget will actually hand to the system.
    ///
    /// One place decides, so the widget cannot draw a button that opens something
    /// other than what the editor showed. The `nil` case is the `.systemShortcut`
    /// route: there is no URL, because the system holds the target as an opaque
    /// reference we never learn — see ``LaunchStrategy``. It is `nil` rather than
    /// an empty URL so the widget's `switch` has a branch that cannot be mistaken
    /// for a link that merely failed to parse.
    public var launchURL: URL? {
        switch launchRoute {
        case .universalLink: universalLink
        case .bounce: url
        case .systemShortcut: nil
        }
    }

    /// How this tile will open, decided from the tile itself.
    ///
    /// Not a stored setting and not a user choice. It used to be both, and the
    /// editor offered 直接打开 / 经 AppFolder 中转 as if they were preferences —
    /// but the picker was really answering "can this work at all", and a user who
    /// picked 直接打开 for an app with no universal link got a tile that lit up
    /// and did nothing. That is the `地图` bug from `docs/research/04-实现笔记.md`,
    /// and removing the choice is what makes it unrepresentable.
    ///
    /// A universal link wins when there is one: it opens with no visible hop.
    /// Otherwise the scheme goes through AppFolder, which is the only route the
    /// platform allows for a custom scheme — a widget's own `Link` opens its host
    /// app and nothing else. There is no third option to fall through to;
    /// `SystemShortcut` is excluded because it cannot be constructed, see
    /// ``LaunchStrategy``.
    public var launchRoute: LaunchStrategy {
        if universalLink != nil { return .universalLink }
        return url != nil ? .bounce : strategy
    }

    /// Whether tapping this tile can reach its target at all.
    ///
    /// False only for a tile with no URL to open — the state the widget cannot
    /// do anything with, where a silent tile is a decision the app made rather
    /// than a mystery the user has to debug by tapping.
    ///
    /// Under the old stored-strategy rule this was also false for "直接打开" on an
    /// app with no universal link, which was the 地图 bug. That state is now
    /// unrepresentable: the derivation sends such a tile down the bounce route,
    /// where it at least reaches AppFolder and can report the failure.
    public var canLaunch: Bool {
        switch launchRoute {
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
            // Carried so that an entry with no App Store id — Apple's own apps —
            // still draws something recognisable. A catalogue entry can gain a
            // real id later, and the symbol steps aside on its own because the
            // icon view prefers fetched artwork when there is any.
            symbolName: app.symbolName,
            universalLinkString: app.universalLink
        )
    }

    /// A tile for an app the catalogue does not know.
    ///
    /// The escape hatch. Every other construction path starts from a ``KnownApp``
    /// and therefore from a scheme somebody verified; this one starts from a name
    /// and a scheme the *user* supplied, which is the only way to reach an app
    /// outside the catalogue at all.
    ///
    /// `catalogID` is deliberately left `nil` rather than set to something
    /// synthetic. It means "this tile did not come from the catalogue", which is
    /// exactly the truth, and ``LibraryRepair`` reads it that way — it will not
    /// backfill a universal link onto a tile it cannot resolve. A made-up id would
    /// make the repair code search for an entry that does not exist and, worse,
    /// make a future catalogue entry with that id silently adopt this tile.
    ///
    /// The app keeps its App Store id, so artwork comes from the same
    /// ``IconStore`` path as everything else with no special case.
    public init(title: String, scheme: String, appStoreID: Int?, symbolName: String? = nil) {
        self.init(
            kind: .app,
            title: title,
            urlString: scheme,
            appStoreID: appStoreID,
            catalogID: nil,
            symbolName: symbolName
        )
    }
}

/// A group of tiles shown as one Home Screen widget — the "big folder".
public struct Folder: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// Ordered; the widget lays these out row-major.
    public var tiles: [FolderTile]
    /// The colour this folder's plate is drawn in, as `#RRGGBB`.
    ///
    /// Empty means "no colour chosen", which is why it stays a `String` rather
    /// than becoming a ``FolderTint``: that is what every library on disk already
    /// holds, and a missing colour is a real state — see
    /// ``FolderTint/defaultTint``.
    public var colorHex: String
    /// How the widget fills the plate under the icons. See ``FolderPlate``.
    public var plate: FolderPlate
    /// Whether each icon in the widget carries its name underneath.
    public var showsTitles: Bool
    /// How much of the grid goes to icons rather than to the gaps between them,
    /// 0…1. See ``FolderGridMetrics/gapShare(forIconScale:)`` for what the
    /// number does — it is a share of the widget's width, not a size.
    public var iconScale: Double
    /// Whether the small widget shows a 3 × 3 or a 2 × 2 grid. See ``FolderGrid``.
    public var grid: FolderGrid
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        tiles: [FolderTile] = [],
        colorHex: String = "",
        plate: FolderPlate = .default,
        showsTitles: Bool = false,
        iconScale: Double = FolderGridMetrics.defaultIconScale,
        grid: FolderGrid = .default,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.tiles = tiles
        self.colorHex = colorHex
        self.plate = plate
        self.showsTitles = showsTitles
        self.iconScale = iconScale
        self.grid = grid
        self.updatedAt = updatedAt
    }

    /// Decodes leniently, for the same reason ``FolderLibrary`` does: synthesized
    /// `Codable` ignores property defaults when a key is absent, so adding
    /// `plate` and `showsTitles` would have failed the decode of every library
    /// written before them — and a failed decode is not a warning here, it is
    /// ``FolderStore`` moving the whole file aside as `.corrupt` and starting
    /// empty. A schema addition would have cost the user every folder they had.
    ///
    /// `colorHex` is tolerant in the other direction too: it has never been
    /// written by any UI — the field has been declared since the first commit and
    /// nothing ever set it — so an absent key is the normal case, not the edge.
    ///
    /// The `try?` around `plate` covers the *other* half of the same bargain, and
    /// it is not the same thing as `decodeIfPresent`: that one tolerates an
    /// absent key and still throws on a present-but-unrecognised value. A
    /// `"plate": "holographic"` — written by a newer build, or by hand — would
    /// take the library down exactly like a missing key would have. Same
    /// reasoning as ``FolderCoding/makeDecoder()``'s two date shapes, and it has
    /// the same blast radius if it is got wrong.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tiles = try container.decodeIfPresent([FolderTile].self, forKey: .tiles) ?? []
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        plate = (try? container.decodeIfPresent(FolderPlate.self, forKey: .plate)) ?? .default
        showsTitles = try container.decodeIfPresent(Bool.self, forKey: .showsTitles) ?? false
        // A library written before this existed decodes to the midpoint, which
        // is the layout it was already being drawn at — see
        // ``FolderGridMetrics/defaultIconScale``. Anything outside 0…1 is
        // clamped rather than rejected: a hand-edited or corrupt value should
        // give the user a folder with an odd size, not no folder at all.
        iconScale = min(max(
            try container.decodeIfPresent(Double.self, forKey: .iconScale)
                ?? FolderGridMetrics.defaultIconScale,
            0
        ), 1)
        // Same bargain as `plate` above, for the same reason: an unrecognised
        // value — written by a newer build, or by hand — must not take the
        // library down. `decodeIfPresent` alone would tolerate an absent key and
        // still throw on a present-but-unknown one, and here a throw means
        // `FolderStore` quarantines the file and the user loses every folder.
        grid = (try? container.decodeIfPresent(FolderGrid.self, forKey: .grid)) ?? .default
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
