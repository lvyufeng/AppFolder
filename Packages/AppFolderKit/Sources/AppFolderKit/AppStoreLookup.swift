import Foundation

/// One app as the App Store describes it.
///
/// ## Why this exists
///
/// iOS exposes no way to list the apps a user has installed — see
/// `docs/research/02-平台限制.md` for the exhaustive sweep, which ruled out every
/// candidate including `FamilyActivityPicker` (opaque tokens), `MarketplaceKit`
/// (EU only), and `IntentApplication` (exported in a `.tbd`, declared in no
/// `.swiftinterface`, so unreachable from Swift).
///
/// So a launcher cannot ask "what is on this phone". It can only ask "what does
/// this app look like", and the public iTunes Search API answers that without a
/// key. That is a strictly worse question — it cannot say whether the app is
/// actually installed — but it is the one that is answerable, and it is enough
/// to build a tile, because what a tile needs is a name, artwork, and an App
/// Store id.
///
/// The App Store id is the load-bearing field. It is what makes a discovered app
/// *matchable* against ``AppCatalog``: an app the catalogue already knows yields
/// its verified URL scheme for free, so the user never has to understand what a
/// scheme is. Only when no entry matches does the app fall through to
/// ``SchemeGuess``.
public struct AppStoreLookup: Sendable, Hashable, Identifiable {
    /// ``trackID``, except for a hand-entered app.
    ///
    /// The manual path builds one of these with no App Store id at all, so the id
    /// cannot simply be `trackID` — two hand-entered apps would share id `0`, and
    /// SwiftUI would treat them as the same sheet. Falls back to the name, which
    /// is what the user typed and therefore what distinguishes them.
    public var id: String { trackID == 0 ? "manual:\(name)" : "store:\(trackID)" }
    /// The App Store id, which is the same number as `FolderTile.appStoreID`.
    public let trackID: Int
    /// The app's bundle identifier, e.g. `com.gotokeep.keep`.
    ///
    /// Present in the search response and kept because ``SchemeGuess`` reads it —
    /// it is the best available hint at a URL scheme. It is *not* usable for
    /// anything else: iOS gives an app no handle on another app from a bundle id,
    /// which is the whole reason this type has to exist in the first place.
    public let bundleID: String?
    public let name: String
    /// The developer, shown to disambiguate same-named apps.
    ///
    /// Not decoration. Searching "Keep" returns Keep, Apple 健身, and a
    /// step-counter app; without the seller the user cannot tell which row is the
    /// one on their Home Screen.
    public let sellerName: String?
    /// `artworkUrl512` when Apple supplies it, which is nearly always.
    public let artworkURL: String?

    public init(
        trackID: Int,
        bundleID: String?,
        name: String,
        sellerName: String?,
        artworkURL: String?
    ) {
        self.trackID = trackID
        self.bundleID = bundleID
        self.name = name
        self.sellerName = sellerName
        self.artworkURL = artworkURL
    }
}

extension AppStoreLookup {
    /// The region to search in, when the caller has no better answer.
    ///
    /// Apple resolves some names differently by storefront — 抖音 is 抖音 in the
    /// Chinese store and TikTok elsewhere — so the storefront is not cosmetic.
    /// The app reads the real one from StoreKit and passes it in; this is the
    /// fallback for a caller that cannot, and `cn` is the right guess for this
    /// app's audience.
    public static let defaultCountry = "cn"

    /// A placeholder for an app the user is describing by hand.
    ///
    /// Track id 0 is the sentinel ``id`` already uses to mean "not from the App
    /// Store", so a manual entry needs no new case. Exists because
    /// ``SchemeEntryView`` takes one of these to render its header, and the manual
    /// path has a name but nothing else.
    public static func manual(name: String) -> AppStoreLookup {
        AppStoreLookup(trackID: 0, bundleID: nil, name: name, sellerName: nil, artworkURL: nil)
    }

    /// The public iTunes Search endpoint for a free-text term.
    ///
    /// No key and no authentication: it is the same endpoint the App Store web
    /// pages use. `entity=software` restricts results to iOS apps, which is what
    /// keeps a search for "微信" from returning music and books.
    public static func searchURL(term: String, country: String = defaultCountry, limit: Int = 12) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components.url
    }

    /// The public iTunes Lookup endpoint, for resolving ids to apps.
    ///
    /// The counterpart to ``searchURL(term:country:limit:)``: search goes from a
    /// name to an id, and this goes from an id to everything else. It is what
    /// makes a shared App Store link useful — the link carries only a track id,
    /// and a track id alone cannot name a tile or fetch an icon.
    ///
    /// `country` is optional on purpose. Omitting it lets the request resolve
    /// against the device's own storefront, which is right when the app is sold
    /// there; passing the region parsed out of the link is right when it may not
    /// be. The endpoint treats "no such app" and "not sold in this storefront"
    /// identically — a 200 with an empty `results` — so a caller that needs the
    /// app should be prepared to try more than one.
    ///
    /// Several ids may be sent in one request; Apple returns a row per id it found.
    public static func lookupURL(ids: [Int], country: String? = nil) -> URL? {
        let clean = ids.filter { $0 > 0 }
        guard !clean.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var items = [URLQueryItem(name: "id", value: clean.map(String.init).joined(separator: ","))]
        if let country, !country.isEmpty {
            items.append(URLQueryItem(name: "country", value: country))
        }
        components.queryItems = items
        return components.url
    }

    /// The search response, parsed.
    ///
    /// A pure function of the bytes, so the tests can feed it real response
    /// shapes without a network, and so a malformed response is a test case
    /// rather than a crash nobody reproduces.
    ///
    /// Returns `[]` rather than throwing for anything unreadable. The caller's
    /// next move is the same in every failure case — show "nothing found" and
    /// leave the manual path available — so a typed error would only be
    /// re-flattened at the call site.
    ///
    /// Rows missing an id or a name are dropped rather than defaulted. Both are
    /// required to build a tile, and a row that cannot become a tile is not worth
    /// showing: the user would tap it and get an app with no name and no artwork.
    public static func parse(_ data: Data) -> [AppStoreLookup] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]]
        else { return [] }

        return results.compactMap { row in
            guard
                let trackID = row["trackId"] as? Int,
                let name = row["trackName"] as? String,
                !name.isEmpty
            else { return nil }

            return AppStoreLookup(
                trackID: trackID,
                bundleID: row["bundleId"] as? String,
                name: name,
                sellerName: row["sellerName"] as? String,
                artworkURL: row["artworkUrl512"] as? String ?? row["artworkUrl100"] as? String
            )
        }
    }
}