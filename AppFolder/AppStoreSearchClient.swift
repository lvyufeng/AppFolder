import AppFolderKit
import Foundation
import StoreKit

/// Searches the public iTunes Search API for apps by name.
///
/// ## Why App Store search, and what it is not
///
/// iOS gives no way to list what the user has installed — see
/// `docs/research/02-平台限制.md`. So an app the curated ``AppCatalog`` does not
/// hold has no path into a folder at all, which is the gap this closes.
///
/// The honest framing: this answers *"does an app by this name exist on the App
/// Store"*, which is **not** the same question as *"do you have it installed"*.
/// The user is expected to search for an app they can see on their own Home
/// Screen, so for them the second question is already answered and this is just
/// how they name it. A search result is therefore never labelled "已安装" — that
/// label comes from ``InstallationProber`` and means something specific here.
///
/// ## Storefront
///
/// The search is pinned to the device's real storefront rather than defaulting to
/// `cn`. Name resolution differs by region in ways that matter: 抖音 is 抖音 in
/// the Chinese store and TikTok elsewhere, so a fixed storefront would show the
/// wrong app to anyone travelling or living abroad. `Storefront.current` is
/// available without any entitlement.
///
/// An actor, matching ``IconStore``: one in-flight request per term, and a small
/// memory cache so that typing and deleting a letter does not re-query.
actor AppStoreSearchClient {
    static let shared = AppStoreSearchClient()

    /// Results already fetched, keyed by `country|term`.
    ///
    /// Bounded because it is fed by a text field. A handful of terms is the whole
    /// useful working set — the user searches once and picks — and an unbounded
    /// dictionary keyed by everything they typed is a slow leak.
    private var cache: [String: [AppStoreLookup]] = [:]
    private var order: [String] = []
    /// Single-app resolutions by track id, kept apart from the search cache
    /// because the values have different types and the keys cannot collide.
    private var lookupCache: [String: AppStoreLookup] = [:]
    private var lookupOrder: [String] = []
    private static let cacheLimit = 24

    /// The storefront to search, resolved on first use.
    ///
    /// `nil` until asked. ``Storefront/current`` is `async` and can block on its
    /// first call, so it is read inside ``search(term:country:)`` rather than in
    /// the initialiser — an actor that cannot be constructed without awaiting
    /// could not be a `static let`.
    private var resolvedCountry: String?

    /// Searches, or returns `nil` if the request could not be made.
    ///
    /// An empty array means "the search worked and found nothing", which the
    /// caller must show differently from `nil` — "could not reach the App Store".
    /// Collapsing the two would tell a user with no signal that their app does not
    /// exist.
    func search(term: String, country overrideCountry: String? = nil) async -> [AppStoreLookup]? {
        // Resolved into a local first, so the `await` is a statement rather than an
        // async call sitting inside the `??` autoclosure — which is not allowed to
        // be async.
        let storefront: String
        if let overrideCountry {
            storefront = overrideCountry
        } else {
            storefront = await self.storefront()
        }
        let key = "\(storefront)|\(term)"
        if let cached = cache[key] { return cached }

        guard let url = AppStoreLookup.searchURL(term: term, country: storefront) else { return [] }

        var request = URLRequest(url: url)
        // The default timeout is 60s, which for a search field is an eternity —
        // the user has typed three more letters by then and the response would
        // land against a stale query.
        request.timeoutInterval = 8

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            http.statusCode == 200
        else { return nil }

        // Parsed off the main actor: JSON decoding of a 12-result payload is
        // small but this is the actor's whole job.
        let results = AppStoreLookup.parse(data)
        remember(results, for: key)
        return results
    }

    /// Resolves a track id to the app it names.
    ///
    /// The counterpart to ``search(term:country:)``, and what a shared App Store
    /// link needs: the link carries an id and nothing else, so the name, bundle id
    /// and artwork all have to be looked up before a tile can be built.
    ///
    /// Several storefronts are tried, because the lookup endpoint cannot say
    /// *which* storefront holds an app — an app not sold in the one the request
    /// resolves against comes back as a 200 with an empty `results`, which is
    /// indistinguishable from an id that does not exist. Since the whole point of
    /// this path is apps bought under a different account or region, trying only
    /// the device's storefront would fail on exactly the cases it exists for.
    ///
    /// The region parsed out of the link is tried first when there is one; it is a
    /// hint, not a filter, so a wrong or missing one costs a request rather than
    /// the whole lookup.
    func lookup(trackID: Int, region: String? = nil) async -> AppStoreLookup? {
        let key = "lookup|\(trackID)|\(region ?? "")"
        if let cached = lookupCache[key] { return cached }

        var countries: [String?] = []
        if let region { countries.append(region) }
        countries.append(nil)
        countries.append(contentsOf: Self.fallbackCountries)
        // Deduplicated but order-preserving: the link's own region must stay first,
        // and `nil` (the device's storefront) second.
        var seen: Set<String> = []
        let ordered = countries.filter { seen.insert($0 ?? "\u{0}").inserted }

        for country in ordered {
            guard let url = AppStoreLookup.lookupURL(ids: [trackID], country: country) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let first = AppStoreLookup.parse(data).first
            else { continue }

            rememberLookup(first, for: key)
            return first
        }
        return nil
    }

    /// Storefronts tried after the link's own and the device's.
    ///
    /// The same list the region picker offers, and now literally so: it comes
    /// from ``AppStoreRegions/codes`` rather than being written out again here.
    /// The two used to be separate literals that had to be kept in step by hand,
    /// and one of them was wrong — `"uk"` in this array, where the App Store's
    /// code for the United Kingdom is `gb`.
    ///
    /// ``lookup(trackID:region:)`` is where a wrong code is *cheap*: it requires
    /// `statusCode == 200` and otherwise falls through to the next storefront, so
    /// a refused code costs one round trip and nothing else. ``search(term:country:)``
    /// is not so forgiving — it makes the same check and answers `nil`, which the
    /// picker reads as *"could not reach the App Store"* and reports as a network
    /// fault. One list, so that the two methods can only ever be wrong together,
    /// with a test on the code that catches it once.
    private static let fallbackCountries: [String?] = AppStoreRegions.codes

    private func rememberLookup(_ result: AppStoreLookup, for key: String) {
        if lookupCache[key] == nil {
            lookupOrder.append(key)
            if lookupOrder.count > Self.cacheLimit {
                lookupCache.removeValue(forKey: lookupOrder.removeFirst())
            }
        }
        lookupCache[key] = result
    }

    /// The device's real storefront, resolved once and remembered.
    ///
    /// Falls back to ``AppStoreLookup/defaultCountry`` rather than failing: a
    /// storefront the system will not report is not a reason to refuse to search,
    /// and for this app's audience the default is the likely right answer.
    func storefront() async -> String {
        if let resolvedCountry { return resolvedCountry }

        // `Storefront.current` is optional: nil before the first transaction, or
        // where there is no storefront at all (a managed device, a region without
        // an App Store). Neither is a reason to refuse to search.
        let resolved: String
        if let code = try? await Storefront.current?.countryCode, !code.isEmpty {
            resolved = code.lowercased()
        } else {
            resolved = AppStoreLookup.defaultCountry
        }
        resolvedCountry = resolved
        return resolved
    }

    private func remember(_ results: [AppStoreLookup], for key: String) {
        if cache[key] == nil {
            order.append(key)
            if order.count > Self.cacheLimit {
                cache.removeValue(forKey: order.removeFirst())
            }
        }
        cache[key] = results
    }
}