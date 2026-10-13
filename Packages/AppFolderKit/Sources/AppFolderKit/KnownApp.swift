import Foundation

/// A third-party app we know how to open, described without touching the app.
///
/// iOS exposes no handle on another app — no bundle id lookup, no icon, no
/// install check. The only thing a launcher can hold is a URL that the system
/// will route, so that is what this type is: a human-readable name, the scheme
/// that opens the app, and its App Store id so the real artwork can be fetched
/// from Apple's public lookup API.
public struct KnownApp: Sendable, Hashable, Identifiable {
    /// How much we trust ``scheme``.
    ///
    /// A wrong scheme fails silently — the tile renders, the tap does nothing —
    /// which is a worse experience than the app simply not being listed. So
    /// unverified entries are kept out of the default picker.
    public enum Confidence: Sendable, Hashable {
        /// Cross-checked against the vendor's documentation or a maintained
        /// scheme database.
        case verified
        /// Plausible but unconfirmed. Never shown by default.
        case unverified
    }

    /// Stable slug, e.g. `wechat`. Used for dedup and persistence.
    public let id: String
    /// Display name, localized to zh-Hans where one exists.
    public let name: String
    /// Latin-script name, so search works when the user types "wechat".
    public let englishName: String
    /// The URL scheme, always including the trailing `://`.
    ///
    /// Retained as reference data, not because anything reads it: the widget that
    /// probed with `canOpenURL` and the `.bounce` route that opened a scheme were
    /// both deleted, and ``DirectLaunchWidget`` now reaches its target through
    /// `RunSystemShortcutIntent`, which needs no URL at all. Kept because it is
    /// hand-researched and correct — see `docs/research/02-平台限制.md`.
    public let scheme: String
    /// App Store id, for `artworkUrl512` from the iTunes Search API.
    public let appStoreID: Int?
    /// Grouping label shown in the picker, e.g. `社交`.
    public let category: String
    public let confidence: Confidence
    /// Whether this is one of Apple's own apps rather than a third-party one.
    ///
    /// Live, not cosmetic: ``DirectLaunchIcons/resolve(name:)`` reads it to decide
    /// whether a catalogue entry with no App Store id should have its artwork
    /// looked up by bundle id. Apple's apps have no store listing, so the name
    /// search cannot find them and the bundle id is the only exact handle.
    public let isSystemApp: Bool

    /// An `https://` URL that opens this app without AppFolder appearing, if one
    /// is known to work.
    ///
    /// Retained as reference data, like ``scheme``: it is what the deleted
    /// `.universalLink` route used, and nothing reads it now. Kept because the
    /// two values that exist (`?t=m` for 地图, `apple.news/` for 新闻) are
    /// measurements on a real runtime, and the comment on the 地图 entry records
    /// the whole sweep that produced them.
    public let universalLink: String?

    /// An SF Symbol standing in for the app's icon, when there is no App Store id
    /// to fetch real artwork with.
    ///
    /// Apple's own apps are the reason this exists. They have no App Store id
    /// (they don't ship through the store), so the icon path that every
    /// third-party entry uses has nothing to fetch, and the app cannot reach into
    /// their bundles to ask. It is also *why* they are listed at all: a picker
    /// whose whole first section is blank grey squares reads as broken, and the
    /// system apps are exactly the ones the probe can always find — so they are
    /// exactly the ones that fill that section.
    ///
    /// A symbol is the honest fallback: not the app's real icon, and not
    /// pretending to be.
    public let symbolName: String?

    /// The App Store id of this app *when the name search cannot find it*, found
    /// instead by its bundle id.
    ///
    /// ## Why a second id is needed at all
    ///
    /// ``appStoreID`` is not enough for Apple's own apps, and the reason is that a
    /// name search returns whatever *contains* the name. Measured on the live
    /// endpoint: searching "设置" returned **Safari** (`com.apple.mobilesafari`) as
    /// the first `com.apple.*` row. It would have been pasted onto the slot as if
    /// it were right — see ``DirectLaunchIcons/appleAppID(payload:terms:)``, which
    /// is the fix for that half.
    ///
    /// The bundle id is the one field that cannot be spoofed or mistranslated:
    /// `com.apple.mobilesafari` is Safari in every storefront. So a listing that is
    /// known but unreachable by name gets recorded here, and the runtime looks it
    /// up through `lookup?bundleId=` rather than searching for it. That covers the
    /// apps whose listing *exists* but is stored under a different name than the
    /// device shows — 地图 is listed as 「Apple地图」, and the name search misses it.
    ///
    /// It does **not** cover an app with no listing at all. 设置 is one; the App
    /// Store is the other, and the App Store is worse, because there *is* a
    /// plausible wrong answer sitting one search away (App Store Connect). Neither
    /// gets an id here: when no correct artwork exists, an id can only name a
    /// *different* app, and the symbol is the honest outcome. See the `appstore`
    /// entry in ``AppCatalog`` for what went wrong when one was recorded anyway.
    ///
    /// ## Why it is optional and mostly empty
    ///
    /// It is a *fallback*, not the preferred path: the live search is tried first
    /// because it adapts to the storefront, and this only answers when the search
    /// fails. `nil` for every third-party app — they do not have this problem, and
    /// adding ids by hand is the fragility this field exists to avoid, not to
    /// introduce.
    ///
    /// Left at the end of the initializer on purpose, so every existing entry that
    /// does not set it reads exactly as before.
    public let storeAppID: Int?

    public init(
        id: String,
        name: String,
        englishName: String,
        scheme: String,
        appStoreID: Int? = nil,
        category: String,
        confidence: Confidence = .verified,
        isSystemApp: Bool = false,
        universalLink: String? = nil,
        symbolName: String? = nil,
        storeAppID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.scheme = scheme
        self.appStoreID = appStoreID
        self.category = category
        self.confidence = confidence
        self.isSystemApp = isSystemApp
        self.universalLink = universalLink
        self.symbolName = symbolName
        self.storeAppID = storeAppID
    }
}
