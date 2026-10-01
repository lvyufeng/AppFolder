import Foundation

/// An App Store link, parsed down to the one number that matters.
///
/// ## Where these links come from
///
/// iOS lets a user share an app straight from its Home Screen icon — long-press,
/// "分享 App". That menu item is real and operating-system level, not a shortcut
/// anyone added: it lives in `SpringBoardHome.framework` under the localisation
/// key `SHARE_APPLICATION_SHORTCUT_ITEM_TITLE`, and SpringBoard posts it through
/// the standard share sheet (`presentShareSheetForIconView:`,
/// `SBHIconShareSheetActivityItemProvider`).
///
/// What it shares is a **link**, not the app. That is the whole opening: the link
/// carries the App Store track id, and the track id is the key that turns into a
/// verified scheme through ``AppCatalog/entry(appStoreID:)``.
///
/// ## Why this is a pure function
///
/// Everything here is string work on an input the platform hands over verbatim.
/// Keeping it out of the UI means the awkward shapes — a slug that itself
/// contains "id", a music link that is not an app at all, an old `itunes.apple.com`
/// URL that still redirects — are test cases rather than bugs found in the field.
///
/// ## Why the region is optional and stays optional
///
/// The share sheet's own URL is built from a template with no region in it
/// (`https://apps.apple.com/app/id%@`), so a link from this path may well have no
/// storefront at all. That is fine: the track id identifies the app globally, and
/// the region is only a hint for which storefront's metadata to read. Callers that
/// need a region fall back to the device's own — so this type reports `nil` rather
/// than guessing a default that would be indistinguishable from a real answer.
public struct AppStoreLink: Sendable, Hashable {
    /// The App Store track id. Always present; a link without one is not an app link.
    public let trackID: Int
    /// The storefront in the URL, lowercased, or `nil` when the link carries none.
    public let region: String?
    /// The URL this was parsed from, kept so a queue entry can be re-parsed and so
    /// a failure is reportable against the exact string that caused it.
    public let url: URL

    public init(trackID: Int, region: String?, url: URL) {
        self.trackID = trackID
        self.region = region
        self.url = url
    }
}

extension AppStoreLink {
    /// Hosts that serve App Store links. Both spellings are in active use:
    /// `apps.apple.com` is current, `itunes.apple.com` is the older one and still
    /// appears in links that were copied years ago. It 301s to the former, which
    /// is exactly why it has to be accepted here — a redirect never happens inside
    /// a parser.
    private static let hosts: Set<String> = ["apps.apple.com", "itunes.apple.com"]

    /// Schemes a share sheet or a clipboard can carry a link under.
    ///
    /// `itms-appss` is the App Store's own scheme. It is the one that matters most
    /// for a URL arriving from the system rather than from a browser: iOS rewrites
    /// store links to it when it wants the App Store app to handle them, and a
    /// parser that only understood `https` would silently drop exactly the links
    /// the share sheet is most likely to produce.
    private static let schemes: Set<String> = ["https", "http", "itms-appss", "itms-apps", "itms"]

    /// Parses an App Store link, or returns `nil` if this is not one.
    ///
    /// Returns `nil` for everything that is not unambiguously an app: a song, a
    /// podcast, a book, a developer page. Those live on the same hosts and look
    /// similar, and admitting one would produce a tile pointing at nothing.
    public static func parse(_ url: URL) -> AppStoreLink? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host?.lowercased(), hosts.contains(host)
        else { return nil }

        // Work on the path segments rather than the whole string. Everything
        // interesting is positional, and the query string is noise — `mt=8`,
        // `l=zh-Hans`, campaign parameters — none of which change which app this is.
        let rawSegments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // The last segment must be `id<digits>`, and nothing else. Anchoring at the
        // end is what keeps a slug like `.../app/midnight/id123` from being read as
        // an app called "midnight" with whatever id the slug happens to contain —
        // the trailing id is the only one Apple promises.
        guard let last = rawSegments.last else { return nil }
        let idPrefix = "id"
        guard last.hasPrefix(idPrefix) else { return nil }
        let digits = last.dropFirst(idPrefix.count)
        // `Int(_:)` accepts a leading sign and ignores nothing else here, so a bare
        // "-5" or "+5" would parse. Neither is an App Store id.
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let trackID = Int(digits), trackID > 0 else {
            return nil
        }

        // A path with no `/app/` segment is not an app: the same hosts serve
        // `/music/…`, `/podcast/…`, `/book/…` and `/developer/…`, and a link to a
        // song also ends in `id<digits>`. Requiring the marker is what separates
        // them from an app link.
        guard rawSegments.contains("app") else { return nil }

        return AppStoreLink(trackID: trackID, region: region(in: rawSegments), url: url)
    }

    /// Parses the first storefront code out of a link's path, if it has one.
    ///
    /// The shape is `/{region}/app/…`, so the region is only the first segment
    /// when it is not itself `app` — `/app/id123` is the region-less form the
    /// system emits. Two letters is the whole rule: App Store storefronts are
    /// ISO 3166-1 alpha-2, and `us`, `cn`, `hk`, `gb` are what appear in practice.
    ///
    /// Deliberately not validated against a country list. A storefront this app
    /// does not recognise is still the storefront the link named, and discarding it
    /// would trade a correct-but-unfamiliar region for a wrong fallback.
    private static func region(in segments: [String]) -> String? {
        guard let first = segments.first, first != "app" else { return nil }
        let lowered = first.lowercased()
        guard lowered.count == 2, lowered.allSatisfy(\.isLetter) else { return nil }
        return lowered
    }

    /// Parses the first App Store link out of arbitrary text.
    ///
    /// For text arriving from somewhere that is not a typed URL — a shared string,
    /// a clipboard entry. The first match wins, because any App Store app link in
    /// such a string is almost certainly *the* link; a message containing two is a
    /// message the user is reading, not pasting.
    ///
    /// Returns `nil` when nothing matches, which is the common case and must be
    /// cheap: this runs on every paste.
    public static func parseFirst(in text: String) -> AppStoreLink? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            guard let matchRange = Range(match.range, in: text),
                  let url = URL(string: String(text[matchRange])),
                  let link = parse(url)
            else { continue }
            return link
        }
        return nil
    }
}