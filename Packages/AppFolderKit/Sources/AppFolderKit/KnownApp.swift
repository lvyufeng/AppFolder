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
    public let scheme: String
    /// App Store id, for `artworkUrl512` from the iTunes Search API.
    public let appStoreID: Int?
    /// Grouping label shown in the picker, e.g. `社交`.
    public let category: String
    public let confidence: Confidence
    /// Whether this is one of Apple's own apps rather than a third-party one.
    ///
    /// Not cosmetic — it changes what the probe can learn. `canOpenURL` enforces
    /// `LSApplicationQueriesSchemes` against third-party apps and not against
    /// Apple's, so a system app can be detected without spending any of the
    /// budget. See ``AppCatalog/queriedSchemes`` for the measurements.
    public let isSystemApp: Bool

    /// An `https://` URL that opens this app without AppFolder appearing, if one
    /// is known to work.
    ///
    /// Separate from ``scheme`` because the two are not interchangeable. The
    /// scheme is what `.bounce` needs — it is exact, and `open(_:)` routes it
    /// straight to the app. This is what `.universalLink` needs, and it only
    /// exists for apps that publish such a URL *and* that we have measured
    /// landing in the app rather than in a browser.
    ///
    /// Being here is a claim backed by a measurement on a real runtime, not a
    /// guess from a domain name. A wrong value produces a tile that opens Safari,
    /// which looks like a working tap and is therefore worse than no entry.
    ///
    /// `nil` for almost everything. Very few apps publish a link whose whole
    /// purpose is "open me", and a deep link into a specific screen is not a
    /// substitute: a launcher tile should land where the Home Screen icon does.
    public let universalLink: String?

    public init(
        id: String,
        name: String,
        englishName: String,
        scheme: String,
        appStoreID: Int? = nil,
        category: String,
        confidence: Confidence = .verified,
        isSystemApp: Bool = false,
        universalLink: String? = nil
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
    }

    /// The scheme without `://`, which is the form `LSApplicationQueriesSchemes`
    /// and `URL.scheme` both use.
    public var schemeName: String {
        scheme.replacingOccurrences(of: "://", with: "")
    }
}
