import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Resolves a direct-launch slot's app and fetches its artwork where the widget can read it.
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
/// The name is enough to get the artwork back. The bundled catalogue answers for
/// the apps it knows; anything else — which is *most* apps, the catalogue is a
/// curated 74 — is looked up in the App Store's public search endpoint. That costs
/// a request per newly seen app, and the result is written to the App Group so the
/// widget's synchronous render always has something to draw, which is the rule the
/// widget's own icon cache is built on.
///
/// ## Why the lookup lives here, in the shared package
///
/// The input is a *name* — the only thing the system hands back for a slot — and
/// the caller is the widget extension, which cannot reach anything in the app
/// target. So the lookup has to sit on the plain types both processes share. (The
/// app used to carry a parallel `IconStore` that resolved *tiles* by App Store id
/// and returned `UIImage`; it went with the folder editor, which was its only
/// caller.)
public enum DirectLaunchIcons {
    /// Where artwork lives inside the App Group.
    public static let directoryName = "Icons"

    /// The session every lookup goes through, with a budget short enough to fit a
    /// widget's timeline build.
    ///
    /// ## Why not `URLSession.shared`
    ///
    /// Its default request timeout is **60 seconds** and it sets no resource
    /// timeout, and these calls run inside ``DirectLaunchWidget``'s timeline build,
    /// which WidgetKit aborts when it overruns. One black-holed request — a captive
    /// portal, packet loss — would therefore stall the build past its budget, so the
    /// entry the build was going to return never commits and the widget keeps its
    /// stale content until the next refresh, which pays the same cost again. The
    /// budget here is deliberately short: a lookup that cannot answer in a few
    /// seconds is better abandoned, and retried on the next timeline, than allowed
    /// to spend the render.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    /// The bytes for a URL, or `nil` if the request failed for any reason.
    ///
    /// `nil` means *unreachable* — offline, DNS, timeout — and never "the store has
    /// no such app". Every caller has to keep those apart, because one of them may
    /// become a permanent, unexpiring miss if it is mistaken for the other; see
    /// ``SearchOutcome``.
    private static func request(_ url: URL) async -> Data? {
        // The build's budget, or none at all. `nil` is every caller that is not
        // the widget's provider — the app's search screen, the tests — where the
        // network is deliberately unbounded. See ``Budget``.
        if let budget = Budget.current, !budget.claim() { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode)
        else { return nil }
        return data
    }

    // MARK: - The render-path budget

    /// The freshest instant any request may still be started at, shared by every
    /// resolve in one timeline build.
    //
    // ## Why this exists
    //
    // The per-request timeouts bound each *request*; nothing bounded the *build*.
    // A timeline provider resolves its slots sequentially, and every slot that is
    // neither pinned nor already cached can reach the network — a catalogue entry
    // whose artwork is missing, an Apple app whose id is not bundled, or a plain
    // store search. With one request allowed to take the 5 s request timeout, a
    // grid of twenty apps could hold the provider open for a minute and a half,
    // and the budget the extension is actually given is a fraction of that. At the
    // end of it WidgetKit discards the entry and the widget keeps stale content —
    // so the work was not merely slow, it was wasted.
    //
    // This box makes a build's whole network allowance one deadline rather than
    // twenty. Note it is a *start* deadline and not a wait: a request already in
    // flight runs to its own 5 s timeout, which is the bound the per-request
    // configuration already provides. A slot past the deadline resolves to
    // ``Source/none`` for this build and is retried, unfrozen, on the next — the
    // same treatment as ``SearchOutcome/unreachable``.
    //
    // Without a box — running in a test or a tool — the network is unbounded, as
    // it was before. The widget always sets one.
    final class Budget: @unchecked Sendable {
        /// How long after ``init(requests:allowance:startedAt:)`` a request may
        /// still start.
        ///
        /// Exposed to the initializer rather than fixed so a test can drive the
        /// clock's effect without waiting on it: a zero allowance refuses at once,
        /// a large one never expires within a test's lifetime. The default is what
        /// ships.
        private let allowance: TimeInterval
        /// How many requests the build may make in total.
        ///
        /// A *count*, not just a deadline. The first version of this allowed one
        /// request per build, and that was simply broken: an app the catalogue does
        /// not know needs **two** — search for its id, then fetch the artwork — so
        /// the artwork fetch was always refused and no icon from the search path
        /// could ever reach the disk. Every one of those slots redrew a placeholder
        /// on every timeline, forever. The count is what a build's slot capacity
        /// justifies; see ``defaultRequests``.
        private let requests: Int
        private let startedAt: Date
        private let lock = NSLock()
        private var consumed = 0

        init(
            requests: Int = Budget.defaultRequests,
            allowance: TimeInterval = Budget.defaultAllowance,
            startedAt: Date = Date()
        ) {
            self.requests = requests
            self.allowance = allowance
            self.startedAt = startedAt
        }

        /// Whether a request may start now, claiming one of the build's slots.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard consumed < requests, Date().timeIntervalSince(startedAt) < allowance else {
                return false
            }
            consumed += 1
            return true
        }

        /// The shipping ceiling — under the 5 s request timeout, so the deadline is
        /// what a long build meets first rather than the transport.
        static let defaultAllowance: TimeInterval = 4

        /// Eight. Comfortably more than the few slots that need a network answer in
        /// a build — the catalogue covers the rest — and far short of the twenty a
        /// runaway grid could want. With the 4 s deadline above it, the two together
        /// bound a build to roughly one request's worth of waiting in the common
        /// case.
        static let defaultRequests = 8

        /// The budget in force, scoped to one timeline build.
        ///
        /// ## Why this is a `@TaskLocal` and not a static
        ///
        /// A static would be process-wide, and this process runs more than one build
        /// at a time: WidgetKit calls `snapshot` for the widget gallery while
        /// `timeline` serves a real refresh, and one extension process can host
        /// several widget instances. With a static, build A's cleanup would clear the
        /// shared slot while build B was still looping — so B's remaining requests
        /// would go out **unbounded**, the exact failure this exists to prevent — and
        /// B's setup could reset the budget A was still spending. A task-local has
        /// neither problem: each build runs in its own task, so each task carries its
        /// own budget and no build can touch another's. It also removes the
        /// unsynchronised mutable static entirely.
        @TaskLocal static var current: Budget?
    }

    /// Opens the network budget for one timeline build.
    ///
    /// Called by the widget's provider around its resolve loop — the only place
    /// that knows where a build starts and ends. It must be used as
    /// ``Budget/withBudget(perform:)`` rather than called for its side effect:
    /// a task-local is only visible to the task that sets it and its children, and
    /// it is restored when the call returns, so nothing has to be cleaned up and an
    /// aborted build cannot leave a budget behind for the next one.
    public static func withBudget<T>(_ body: () async -> T) async -> T {
        await Budget.$current.withValue(Budget()) { await body() }
    }

    /// What a slot resolved to, so the caller can draw it without asking again.
    public struct Resolved: Sendable, Equatable {
        public let name: String
        public let appStoreID: Int?
        /// The selected artwork storefront; nil retains the legacy US/CN lookup.
        public var country: String? = nil
        public let symbolName: String?
        /// Which rule produced ``appStoreID``.
        ///
        /// Carried so the caller can tell a name the user pinned from one that was
        /// guessed, and so the widget's log says *why* it drew what it drew — the
        /// question that had to be reconstructed by hand every time an icon was
        /// wrong. See ``Source``.
        public let source: Source
        /// Temporary lookup failures need a later timeline, unlike confirmed misses.
        public var shouldRetry: Bool = false
    }

    /// How a slot's app was decided.
    ///
    /// The raw values are written into the app's observed-slot records, so they are
    /// a wire format between the widget and the app: rename one only with a decoder
    /// that maps an unknown value to ``Source/none``.
    public enum Source: String, Sendable, Equatable {
        /// The user said so. See ``DirectLaunchOverrides``.
        case override
        /// A catalogue entry, which is exact and needs no request.
        case catalogue
        /// Apple's own app, found by bundle id.
        case system
        /// An App Store search, which is a guess that can be wrong.
        case search
        /// Asked before and the store could not name it.
        case miss
        /// Nothing resolved; the slot draws its placeholder.
        case none
    }

    /// How one name search ended, which is not the same question as whether it
    /// found an app.
    ///
    /// ## Why this is three cases and not an `Int?`
    ///
    /// "The store does not carry this app" and "I could not reach the store" both
    /// used to be `nil`, and ``resolve(name:)`` recorded a permanent, unexpiring
    /// miss for either — so a name first seen while offline was marked as one the
    /// store has never heard of, and never looked up again. The widget's timeline
    /// policy is `.never`, so nothing would ever revisit it. Splitting the two lets
    /// only a *clean* empty answer become a miss; a transport failure resolves to
    /// ``Source/none`` for this build and is retried on the next, when the network
    /// may be there.
    enum SearchOutcome: Equatable {
        /// A row that is the app asked about.
        case found(Int)
        /// The store answered, and none of its rows is this app.
        case noMatch
        /// No answer at all — offline, DNS, a timeout, a captive portal.
        case unreachable
    }

    /// Resolves the app behind a slot's display name and makes sure its icon is cached.
    ///
    /// ## The order, and why it is this order
    ///
    /// 1. **The user's own answer** (``DirectLaunchOverrides``). It wins over
    ///    everything, including a catalogue hit and a previous miss, because a
    ///    collision has no correct automatic answer and the user is the only party
    ///    who knows which app they installed.
    /// 2. **The miss cache**, which is a *negative* memory: a name the store could
    ///    not resolve is not asked about again. It sits below the override so that
    ///    pinning a name a search gave up on still works.
    /// 3. The catalogue, Apple's own apps, and finally a live search.
    ///
    /// Steps 1 and 2 are both file and defaults reads — no network — so moving the
    /// miss check in here from the caller costs nothing on the render path.
    ///
    /// - Parameter name: the display name the system showed, which is the app's own
    ///   name and not necessarily the storefront's.
    /// - Returns: the id and symbol to draw, after the artwork is on disk.
    public static func resolve(name: String) async -> Resolved {
        await resolve(name: name, search: searchAppStoreID)
    }

    /// Keeps confirmed misses and temporary network failures independently testable.
    static func resolve(
        name: String,
        search: (String) async -> SearchOutcome
    ) async -> Resolved {
        // The user's answer first. `ensureIcon` reads from disk when the app has
        // already fetched the icon — which it does when the override is set — so
        // the common case here is one file read and no request.
        if let mapping = DirectLaunchOverrides.mapping(name: name) {
            _ = await ensureIcon(appStoreID: mapping.appStoreID, country: mapping.country)
            return Resolved(name: name, appStoreID: mapping.appStoreID, country: mapping.country,
                            symbolName: nil, source: .override)
        }

        // A name already given up on is not searched again. Checked *after* the
        // override so a pin always beats a recorded failure, and *before* the
        // catalogue so the cheap negative answer still short-circuits the work.
        if hasMiss(name: name) {
            return Resolved(name: name, appStoreID: nil, symbolName: nil, source: .miss)
        }

        // The catalogue is tried first because it needs no request and answers
        // exactly; the App Store is the fallback that makes this work for the apps
        // the catalogue has never heard of.
        if let known = AppCatalog.match(name: name) {
            if let id = known.appStoreID {
                _ = await ensureIcon(appStoreID: id)
                return Resolved(name: name, appStoreID: known.appStoreID, symbolName: known.symbolName, source: .catalogue)
            }

            // A catalogue entry with no App Store id is one of Apple's own apps,
            // and the symbol is the stand-in it was given. That stand-in is a grey
            // square where the user expects their calendar, so the store is asked
            // for the real artwork before falling back to it.
            //
            // This used to return immediately, and the cost was exactly one asset:
            // Calendar drew as a grey symbol while every app beside it drew in
            // colour, which read as a rendering bug rather than as a gap in the
            // catalogue. See ``systemAppID(name:englishName:)`` for why the lookup
            // is safe when a plain name search is not.
            //
            // Gated on `isSystemApp` rather than on the missing id alone. The two
            // coincide for every entry a slot can actually name — but not for the
            // catalogue's 自定义链接 placeholder, which is neither a system app nor
            // an app at all, and which the gate keeps out of a lookup that could
            // only ever spend a request to find nothing. See the invariant test in
            // `DirectLaunchMatchTests` for the property this relies on.
            //
            // The symbol is kept even on success: if the artwork fetch fails later,
            // ``DirectLaunchArtwork`` still has something to draw.
            if known.isSystemApp {
                // The entry's own bundle-id lookup first, because it is exact and
                // the search below is not. See ``KnownApp/storeAppID`` for the two
                // mis-assignments that made this necessary — searching "设置"
                // returns Safari, and searching "App Store" returns App Store
                // Connect.
                //
                // Deliberately outside the App Group cache below: this id is in
                // the bundle at compile time, so caching it would only add a way
                // for the bundle and the cache to disagree. It costs no request —
                // ``ensureIcon(appStoreID:)`` reads from disk when the artwork is
                // already there — so there is nothing to save.
                if let id = known.storeAppID {
                    _ = await ensureIcon(appStoreID: id)
                    return Resolved(name: name, appStoreID: id, symbolName: known.symbolName, source: .system)
                }

                // The id is remembered, because the lookup is not free and this
                // path is not rare: expanding any grid that holds one of these
                // runs a whole new timeline, so without the cache every tap on a
                // door would spend a request — on the render path, where the
                // budget is tight and the answer never changes. See
                // ``cachedSystemAppID(name:)``.
                if let cached = cachedSystemAppID(name: name) {
                    // `cached` is itself optional, and the two levels mean
                    // different things: `nil` here is "asked before and the store
                    // has no listing", which must not become another request.
                    guard let id = cached else {
                        return Resolved(name: name, appStoreID: nil, symbolName: known.symbolName, source: .none)
                    }
                    // Reads from disk when the artwork is already there, so this
                    // is not a network call — see ``ensureIcon(appStoreID:)``.
                    _ = await ensureIcon(appStoreID: id)
                    return Resolved(name: name, appStoreID: id, symbolName: known.symbolName, source: .system)
                }
                switch await systemAppID(name: name, englishName: known.englishName) {
                case .found(let id):
                    // Icon first, cache second. This used to be the other way
                    // round, and the cost was exactly the failure the cache exists
                    // to prevent: the id was written down, the build then ran out of
                    // its network budget before fetching the artwork, and every
                    // later build read the id back, skipped the fetch as paid-for,
                    // and drew a placeholder for an app whose icon was never
                    // downloaded. Writing the id only once its bytes are on disk
                    // keeps "cached" meaning "usable".
                    _ = await ensureIcon(appStoreID: id)
                    cacheSystemAppID(id, name: name)
                    return Resolved(name: name, appStoreID: id, symbolName: known.symbolName, source: .system)

                case .noMatch:
                    // The store named neither the localised nor the Latin app —
                    // measured for `News` and `Settings` on the Chinese storefront.
                    // That answer will never change, so it is *remembered*, as the
                    // `0` sentinel ``cachedSystemAppID(name:)`` decodes to `.some(nil)`.
                    //
                    // Without this the lookup had no memory on the failing side: the
                    // success branch wrote the cache and the failure path fell straight
                    // through, so every timeline build re-ran the whole sweep — up to
                    // four sequential requests — for the same app, forever, on the
                    // render path where the budget is tight and the negative cache
                    // exists precisely to avoid this. The `nil` is deliberate: it means
                    // "asked, and the store has no listing", which the check above
                    // reads as a reason to stop rather than a reason to ask again.
                    //
                    // Deliberately not reached by ``SearchOutcome/unreachable``: a
                    // permanent cache entry must never be written from a request that
                    // never got an answer.
                    cacheSystemAppID(nil, name: name)

                case .unreachable:
                    // No answer at all. Leave the cache untouched so a later build —
                    // on a network that works — asks again.
                    return Resolved(name: name, appStoreID: nil, symbolName: known.symbolName,
                                    source: .none, shouldRetry: true)
                }
            }
            return Resolved(name: name, appStoreID: nil, symbolName: known.symbolName, source: .none)
        }

        // A name this store has already been asked about is answered from disk.
        // Without this the search ran on every timeline for every uncached app —
        // see ``cacheSearchID(_:name:)``. Checked after the miss cache and the
        // catalogue, so both still win.
        if let remembered = cachedSearchID(name: name) {
            _ = await ensureIcon(appStoreID: remembered)
            return Resolved(name: name, appStoreID: remembered, symbolName: nil, source: .search)
        }

        switch await search(name) {
        case .found(let id):
            // Icon first, cache second — see the note on ``ensureIcon(appStoreID:)``
            // for why the order cannot be the other way round.
            _ = await ensureIcon(appStoreID: id)
            cacheSearchID(id, name: name)
            return Resolved(name: name, appStoreID: id, symbolName: nil, source: .search)

        case .noMatch:
            // The store answered and has no such app: remembered as a miss (see
            // ``markMiss(name:)``) so the next timeline does not spend another
            // request on the same unknown name.
            markMiss(name: name)
            return Resolved(name: name, appStoreID: nil, symbolName: nil, source: .miss)

        case .unreachable:
            // No answer at all — offline, DNS, a captive portal, a timeout.
            // Deliberately **not** a miss. A miss never expires and is checked
            // before the catalogue, so recording one here would strand an app the
            // store can name the moment the network returns: the slot would show
            // its placeholder forever, and since the timeline policy is `.never`
            // nothing would ever revisit it. This build draws the placeholder and
            // the next one asks again.
            return Resolved(name: name, appStoreID: nil, symbolName: nil, source: .none, shouldRetry: true)
        }
    }

    // MARK: - App Store

    /// The App Store id for one of Apple's own apps, by either of its names.
    ///
    /// ## Why a name search is not enough here, and what makes it safe
    ///
    /// `Calendar`, `Photos`, `Maps`, `News` and `Health` are contested words. A
    /// naive search for `Calendar` on a Chinese storefront returns *Calendars* by
    /// Readdle first and `Google 日历` second — so ``bestMatch(payload:name:)``,
    /// which ranks by name containment, would pick a third party's calendar and
    /// give Apple's app a stranger's icon. That is worse than the grey square it
    /// replaces, which is why this is a separate lookup with a separate rule
    /// rather than a call to the one next door.
    ///
    /// The rule is the bundle id. Apple's apps ship as `com.apple.*` and nothing
    /// else can, so the prefix is an exact test that does not depend on what the
    /// app is called in any storefront. Measured on the live endpoint, and the
    /// reason this works at all: **Apple's system apps do have store listings.**
    /// The catalogue's note that they "don't ship through the store" is true of
    /// installing them and false of the endpoint — they are indexed, which is how
    /// Siri and Spotlight can point at them.
    ///
    /// Both names are tried because the storefront decides which one resolves:
    /// a Chinese device reports the slot as 日历 and an English one as `Calendar`,
    /// and while both returned Apple's row in measurement, the two storefronts do
    /// not always agree on which names exist. `englishName` is the catalogue's own
    /// Latin name for the app, so it costs nothing to try.
    ///
    /// - Returns: ``SearchOutcome/found(_:)`` with the id, ``SearchOutcome/noMatch``
    ///   when the store answers but lists no `com.apple.*` app by either name — the
    ///   honest answer for the few system apps with no listing, whose caller keeps
    ///   the symbol — or ``SearchOutcome/unreachable`` when no request got an
    ///   answer. The last must not be cached as though it were the second: the cache
    ///   is permanent and never expires the entry.
    static func systemAppID(name: String, englishName: String?) async -> SearchOutcome {
        await systemAppID(name: name, englishName: englishName, load: request)
    }

    static func systemAppID(
        name: String, englishName: String?, load: (URL) async -> Data?
    ) async -> SearchOutcome {
        var tried: Set<String> = []
        // Whether any request came back at all. With neither name answered, an empty
        // store is only worth remembering if the store actually spoke.
        var reached = false
        var unreachable = false
        for term in [name, englishName].compactMap({ $0 }) where tried.insert(term).inserted {
            // Every name this entry answers to, so a row matching either the
            // localised or the Latin one is accepted — see ``appleAppID(payload:terms:)``
            // for why the match has to be exact.
            let terms = Set([name, englishName].compactMap { $0 }.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            // The API's default US storefront first, then `cn`, matching
            // ``searchAppStoreID(name:)``. These are search sources, not a
            // statement about the user's account or installed apps.
            for country in [nil, "cn"] as [String?] {
                guard let url = AppStoreLookup.searchURL(term: term, country: country, limit: 6) else { continue }
                guard let payload = await load(url),
                      AppStoreLookup.parseResponse(payload) != nil else {
                    unreachable = true
                    continue
                }
                reached = true
                if let id = appleAppID(payload: payload, terms: terms) { return .found(id) }
            }
        }
        return reached && !unreachable ? .noMatch : .unreachable
    }

    /// The row in a search response that is Apple's app *and* goes by one of the
    /// names asked for, or `nil`.
    ///
    /// ## Why the bundle prefix alone was not enough
    ///
    /// This used to take the first `com.apple.*` row and stop. The prefix is a
    /// sound test of *Apple*, but it says nothing about *which* Apple app, and the
    /// search endpoint matches a term against the whole row — so a slot named
    /// 「设置」 came back with **Safari** and was drawn with Safari's icon, and a
    /// slot named 「App Store」 came back with **App Store Connect**. Both were
    /// measured on the live endpoint; neither is visible as a failure, because a
    /// plausible wrong icon looks like a working tile.
    ///
    /// ## Why an exact name and not a containment match
    ///
    /// Because containment is what produced the Safari answer. Apple's own rows
    /// are indexed under names the user's device does not use — the storefront
    /// calls Maps 「Apple地图」 and Health 「Apple 健康」 — so a *loose* match is
    /// wrong in both directions: too loose and it finds a sibling, too strict and
    /// it finds nothing. Rather than tune that, the apps the exact match misses are
    /// named explicitly in the catalogue via ``KnownApp/storeAppID``, which is a
    /// lookup by bundle id and cannot match a sibling at all.
    ///
    /// - Parameter terms: the names this entry is known by, already lowercased.
    ///   Every one the caller tried, so a row answering to either the localised or
    ///   the Latin name is accepted.
    static func appleAppID(payload: Data, terms: Set<String>) -> Int? {
        AppStoreLookup.parse(payload)
            .first { listing in
                guard listing.bundleID?.hasPrefix("com.apple.") == true else { return false }
                let name = listing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return terms.contains(name)
            }?
            .trackID
    }

    // MARK: - System app cache

    /// Records an id so the next timeline does not look it up again.
    ///
    /// Also records the *absence* of one, as `0`. A system app the store does not
    /// list — measured for `News` and `Settings` on the Chinese storefront — is the
    /// case most in need of remembering, because nothing about the answer will ever
    /// change and the retry would be permanent.
    ///
    /// In the App Group beside the icon cache, so it survives the extension being
    /// torn down between taps. That is the whole point: the widget process is not
    /// long-lived and an in-memory set would be empty each time.
    private static func cacheSystemAppID(_ id: Int?, name: String) {
        guard let url = systemAppCacheURL(name: name) else { return }
        try? Data(String(id ?? 0).utf8).write(to: url, options: .atomic)
    }

    /// The remembered result for a system app, or `nil` if it was never looked up.
    ///
    /// Optional-of-optional on purpose: `nil` means "not asked yet, go and ask"
    /// while `.some(nil)` means "asked, and the store has no listing" — a
    /// distinction that decides whether a request is spent, so it cannot be
    /// collapsed into a single `nil`.
    static func cachedSystemAppID(name: String) -> Int?? {
        guard let url = systemAppCacheURL(name: name),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let stored = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return stored > 0 ? .some(stored) : .some(nil)
    }

    /// The generation of the system-app id cache, and **bump it whenever the rule
    /// that produces the id changes.**
    ///
    /// The cache is keyed on the app's *name*, not on the rule, so a corrected rule
    /// would otherwise keep reading the answers the broken one wrote — forever,
    /// since nothing expires these. That is not hypothetical: `v1` holds the id
    /// ``appleAppID(payload:terms:)`` used to return for 「设置」, which was
    /// **Safari's**. Shipping the fix without this bump would have left the slot
    /// drawing exactly the wrong icon it was fixed to stop drawing, on every device
    /// that had already run the old build.
    ///
    /// Bumping costs one lookup per system app, once, on devices that had the old
    /// file. The stale files are left behind rather than deleted — they are a few
    /// bytes each, and scanning the container root to remove them would run on the
    /// render path for no visible benefit.
    // v4 also retries negative results written from incomplete storefront sweeps.
    private static let systemAppCacheGeneration = "v4"

    private static func systemAppCacheURL(name: String) -> URL? {
        containerDirectory()?.appending(path: "system-\(systemAppCacheGeneration)-\(stableHash(name)).txt")
    }

    /// The generation of the **search** result cache. Bump it whenever the rule
    /// that produces a searched id changes, for the same reason and with the same
    /// cost as ``systemAppCacheGeneration``.
    private static let searchAppCacheGeneration = "v1"

    /// Remembers the id a plain store search found for a name.
    ///
    /// ## Why this had to exist
    ///
    /// ``ensureIcon(appStoreID:)`` caches the *artwork* the search led to, so the
    /// icon is offline from the second render on — but the name → id mapping was
    /// never written down. An app the catalogue does not know is therefore searched
    /// again on **every** timeline, forever, even though its icon is already on
    /// disk: a request per such app per render, on the path where the budget is
    /// tightest, for an answer that cannot change. The system-app branch has cached
    /// its own lookups since it was written; the search branch simply never did.
    ///
    /// A negative answer is not stored here. A name the store did not match goes
    /// through ``markMiss(name:)``, which already has a semantics for "asked and
    /// there is nothing" that a search id cache should not duplicate.
    static func cacheSearchID(_ id: Int, name: String) {
        guard let url = searchAppCacheURL(name: name) else { return }
        try? Data(String(id).utf8).write(to: url, options: .atomic)
    }

    /// The id a search found for this name before, or `nil` if it has not been
    /// looked up. Unlike ``cachedSystemAppID(name:)`` this is a plain optional:
    /// the negative case lives in the miss cache.
    static func cachedSearchID(name: String) -> Int? {
        guard let url = searchAppCacheURL(name: name),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let stored = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              stored > 0
        else { return nil }
        return stored
    }

    private static func searchAppCacheURL(name: String) -> URL? {
        containerDirectory()?.appending(path: "search-\(searchAppCacheGeneration)-\(stableHash(name)).txt")
    }

    /// The App Store id for an app, by name — and, when there is none, *why*.
    ///
    /// Two storefronts are tried, the API's default US first and `cn` second. The
    /// second is not a guess at the user's region — it is the answer for the case
    /// this widget exists to serve: a Chinese app whose *display* name is its
    /// English one ("Alimail"), which the default US search does not match but a
    /// Chinese storefront does.
    ///
    /// A name with no URL to search at all is ``SearchOutcome/noMatch`` rather than
    /// ``SearchOutcome/unreachable``: the term is empty or malformed, and no request
    /// would ever fix that, so it is as final as an empty result.
    static func searchAppStoreID(name: String) async -> SearchOutcome {
        await searchAppStoreID(name: name, search: bestMatch)
    }

    static func searchAppStoreID(
        name: String, search: (URL, String) async -> SearchOutcome
    ) async -> SearchOutcome {
        var reached = false
        var unreachable = false

        if let defaultURL = AppStoreLookup.searchURL(term: name, country: nil, limit: 5) {
            switch await search(defaultURL, name) {
            case .found(let id): return .found(id)
            case .noMatch: reached = true
            case .unreachable: unreachable = true
            }
        }

        if let cnURL = AppStoreLookup.searchURL(term: name, country: "cn", limit: 5) {
            switch await search(cnURL, name) {
            case .found(let id): return .found(id)
            case .noMatch: reached = true
            case .unreachable: unreachable = true
            }
        }

        // One storefront's empty answer cannot prove absence from the other
        // when that request failed. Keep that name retryable after recovery.
        return reached && !unreachable ? .noMatch : .unreachable
    }

    /// Whether one storefront's answer contains the app asked about.
    ///
    /// Ranking the *names* alone does not work, and the failure is not exotic: the
    /// system shows an app's own name, which is routinely not the storefront's. A
    /// slot for 阿里邮箱 arrives as `Alimail`, the store calls it 阿里邮箱, and a
    /// name comparison finds nothing — even though the search endpoint returns that
    /// very app *first*, and every other result is an unrelated mail client.
    ///
    /// So the bundle id is admitted as evidence. The app that calls itself Alimail
    /// has `com.alibaba.alimail.store.catalyst2`, and a result whose bundle id
    /// contains the search term is that app by a stronger argument than a name
    /// match — a display name is marketing, a bundle id is identity.
    ///
    /// The order matters: a name match wins outright, so this can only ever add
    /// hits, never displace a result the name already agreed with.
    ///
    /// A request that fails is ``SearchOutcome/unreachable``, not
    /// ``SearchOutcome/noMatch`` — the difference decides whether the caller writes
    /// a permanent miss; see ``SearchOutcome``.
    static func bestMatch(url: URL, name: String) async -> SearchOutcome {
        guard let payload = await request(url) else { return .unreachable }
        guard AppStoreLookup.parseResponse(payload) != nil else { return .unreachable }
        guard let id = bestMatch(payload: payload, name: name) else { return .noMatch }
        return .found(id)
    }

    /// Picks the app out of a search response.
    ///
    /// Split from the request so the three match rules can be tested against the
    /// exact rows the live endpoint returns — captured from it, not invented. See
    /// `DirectLaunchMatchTests`.
    static func bestMatch(payload: Data, name: String) -> Int? {
        let needle = normalized(name)
        guard !needle.isEmpty else { return nil }
        // Letters and digits only, so a bundle id can be searched for a term that
// contains punctuation or spaces. Whether it is long enough to be worth
// searching is decided where it is used.
        let idNeedle = needle.filter { $0.isLetter || $0.isNumber }

        let rows = AppStoreLookup.parse(payload)

        // 1. The store name is the display name outright.
        if let exact = rows.first(where: { normalized($0.name) == needle }) {
            return exact.trackID
        }

        // 2. The store name *contains* it. This is the common case, not an edge:
        // store names carry decoration the display name drops, so 涨乐's slot
        // arrives as "AI涨乐" and the store calls it "涨乐 - AI涨乐". An earlier
        // version of this only accepted a whole-name or prefix match and threw that
        // correct answer away.
        //
        // Among several containing rows, **the store's own order wins** — the first
        // row, not the shortest. This used to take the shortest name, on the theory
        // that the app whose name is closest to the display name is where the
        // display name came from. That theory is wrong exactly when it matters most:
        // a *name collision*. "Authenticator" alone matches eight apps, and the
        // shortest is "Authenticator ·" by SMM service — a tiny app that merely
        // named itself well — while the store, which knows the vendor, returns
        // Microsoft Authenticator first. So the shortest-name rule handed the slot
        // an icon belonging to a different app, which is a worse failure than a
        // miss: the user sees a real, plausible, wrong icon.
        //
        // The store's ranking is the vendor-aware signal we do not have. We cannot
        // read the developer from the slot (``SystemShortcut`` gives a name and
        // nothing else — see the probe in `DirectLaunchWidget`), so the only party
        // that can weigh the vendor is Apple, and its order already does.
        //
        // This is safe because the ranking was always trustworthy for the case that
        // is *not* ambiguous: 阿里邮箱 is still returned first for "Alimail", and
        // 涨乐 for "AI涨乐", so taking the first containing row agrees with every
        // measurement the shortest-name rule was introduced to satisfy.
        if let containing = rows.first(where: { normalized($0.name).contains(needle) }) {
            return containing.trackID
        }

        // 3. The bundle id contains it — the fallback for a name with no shared
        // characters at all, which is what 阿里邮箱 looks like from a slot the
        // system calls "Alimail". Guarded on length because a two- or three-letter
        // term matches half the store's bundle ids and would attach an unrelated
        // app's icon.
        guard idNeedle.count >= 4 else { return nil }
        return rows.first { row in
            guard let bundleID = row.bundleID else { return false }
            return normalized(bundleID).replacingOccurrences(of: ".", with: "").contains(idNeedle)
        }?.trackID
    }

    /// Case- and whitespace-insensitive form used for every name comparison.
    ///
    /// The strings being compared are written by different people: the system
    /// shows the app's own name, the store carries the storefront's, and they
    /// differ in case and spacing more often than in words.
    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Disk

    /// The PNG bytes for a resolved id, from disk if present and the network if not.
    ///
    /// Public because the app calls it too: when the user pins a slot to an app,
    /// the app fetches that app's artwork *before* asking WidgetKit to reload, so
    /// the first render after the change already has the icon on disk. The widget
    /// never does network at draw time, so without this the tile would blink to a
    /// placeholder while the fetch happened later.
    ///
    /// Idempotent and cheap when the bytes are already there — the disk read wins
    /// over the request — so calling it from both processes is safe.
    public static func ensureIcon(appStoreID id: Int, country: String? = nil) async -> Data? {
        await ensureIcon(appStoreID: id, country: country, directory: containerDirectory(), load: request)
    }

    /// The production cache path with injectable storage and transport for recovery tests.
    static func ensureIcon(
        appStoreID id: Int,
        country: String? = nil,
        directory: URL?,
        load: (URL) async -> Data?
    ) async -> Data? {
        guard let filename = fileName(appStoreID: id, country: country) else { return nil }
        if let cached = cachedIcon(appStoreID: id, country: country, directory: directory) { return cached }
        guard !Task.isCancelled, let data = await fetch(appStoreID: id, country: country, load: load),
              !Task.isCancelled else { return nil }
        if let directory {
            try? data.write(to: directory.appending(path: filename), options: .atomic)
        }
        return data
    }

    /// The artwork already on disk for an id, or `nil` if it has not been fetched.
    ///
    /// The read half of ``ensureIcon(appStoreID:)``, and public for the app's
    /// benefit: the app shows the user the icon the widget will draw, and the only
    /// way to show *that* icon rather than a fresh download is to read the same
    /// file. Fetches nothing — a miss is a miss, not a request.
    public static func cachedIcon(appStoreID id: Int, country: String? = nil) -> Data? {
        cachedIcon(appStoreID: id, country: country, directory: containerDirectory())
    }

    static func cachedIcon(appStoreID id: Int, country: String? = nil, directory: URL?) -> Data? {
        guard let filename = fileName(appStoreID: id, country: country), let directory else { return nil }
        let file = directory.appending(path: filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= artworkByteLimit,
              let data = try? Data(contentsOf: file),
              artworkThumbnail(data) != nil
        else { return nil }
        // Keep valid artwork from older versions, including their 512px cache.
        // Invalid bytes are a miss, so the timeline schedules recovery instead
        // of deciding that a permanently blank tile already has its artwork.
        return data
    }

    /// The store's answer for one of its own URLs, through this module's session.
    ///
    /// Exposed for the app's 修正图标 screen, which searches the store with the same
    /// `searchURL` the widget's automatic matcher uses. It used to call
    /// `URLSession.shared`, whose `timeoutIntervalForRequest` is 60 s and which has
    /// no resource timeout at all — so the one interactive place a user actually
    /// waits on the network had a *worse* bound than the widget's timeline build,
    /// which is the opposite of the intent. Going through here means there is one
    /// timeout policy in the project rather than two.
    ///
    /// `nil` is *unreachable* — offline, DNS, a captive portal, a timeout — and
    /// never "the store has no such app". See ``SearchOutcome`` for why callers
    /// must keep those apart; the negative answer is a clean empty payload, which
    /// arrives as `Data`, not `nil`.
    public static func storeData(url: URL) async -> Data? {
        await request(url)
    }

    /// The App Group's icon directory, created if it is missing.
    ///
    /// Public so a caller can tell "no container" apart from "no icon" — the same
    /// distinction the widget has to make, and the
    /// one that decides whether a widget will find what a preview found.
    public static func containerDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        ) else { return nil }
        let directory = container.appending(path: directoryName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// The file name an icon is cached under, so the resolver and
    /// ``WidgetIconCache`` agree on where a given app's artwork lives.
    public static func fileName(appStoreID: Int) -> String { "\(appStoreID).png" }

    /// Explicit storefronts have independent cache files. Invalid inputs never
    /// become file paths or silently fall back to another storefront's artwork.
    public static func fileName(appStoreID: Int, country: String?) -> String? {
        guard appStoreID > 0 else { return nil }
        guard let country else { return fileName(appStoreID: appStoreID) }
        guard let normalized = AppStoreCountry.normalized(country) else { return nil }
        return "\(appStoreID)-\(normalized).png"
    }

    // MARK: - Misses

    /// The marker file that records a name the store could not resolve.
    ///
    /// Without it, an app the store does not carry would be re-searched on every
    /// timeline — the widget would spend a request each time it redrew, forever, to
    /// learn the same nothing. The miss is remembered for the same reason a hit is.
    ///
    /// The version is part of the file name, and that is the point of it: a miss is
    /// a statement about *the matcher*, not about the app. When the matching rules
    /// change, every marker written under the old rules is an answer to a question
    /// nobody is asking any more — and left in place it would permanently hide apps
    /// the new rules can now find. Bump this whenever ``bestMatch(url:name:)`` or
    /// ``AppCatalog/match(name:)`` changes what they accept.
    // v4 retries markers that may have been produced by invalid responses or
    // by a failed fallback storefront, rather than confirmed empty searches.
    private static let missVersion = 4

    private static func missFileURL(name: String) -> URL? {
        containerDirectory()?.appending(path: "miss-v\(missVersion)-\(stableHash(name)).txt")
    }

    public static func hasMiss(name: String) -> Bool {
        guard let url = missFileURL(name: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func markMiss(name: String) {
        guard let url = missFileURL(name: name) else { return }
        try? Data().write(to: url, options: .atomic)
    }

    /// Forgets that a name could not be resolved.
    ///
    /// Called when the user pins a name to an app: the pin would win anyway — see
    /// the order in ``resolve(name:)`` — but clearing the marker means *unpinning*
    /// later falls back to a fresh search instead of to a "the store has never
    /// heard of this" that was written under an older matching rule.
    static func clearMiss(name: String) {
        guard let url = missFileURL(name: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// A file-name-safe digest of a name.
    ///
    /// `hashValue` is not usable: it is seeded per process, so the widget and the
    /// app would disagree about which file a name maps to and each would write its
    /// own. This is a plain FNV-1a, stable across processes and versions.
    ///
    /// Public because the miss markers are no longer its only reader: the
    /// direct-launch widget names a grid by its slots, which have no id, and needs
    /// the same property — a key the intent's process and the render's process
    /// agree on. See ``WidgetState/directLaunchExpansionKey(slotNames:)``.
    public static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// Test seam: match a response without a request.
    ///
    /// The `url` parameter is unused and exists so the call site reads like the real
    /// one; matching is pure once the bytes are in hand.
    static func matchForTesting(payload: Data, name: String, url: URL) async -> Int? {
        bestMatch(payload: payload, name: name)
    }

    // MARK: - Diagnostics

    /// How large the diagnostic log may grow before it is thrown away.
    ///
    /// The log is appended to on every timeline build and nothing else ever clears
    /// it, so without a bound it grows for the life of the install. 256 KB is many
    /// days of ordinary use and is discarded by the system under storage pressure
    /// anyway; the point of the cap is that the *file the app itself maintains* has
    /// a stated maximum rather than an accidental one.
    private static let logByteLimit = 256 * 1024

    /// Appends a debug-build-only log in the App Group's `Library/Caches`.
    ///
    /// For diagnosing a widget, and only that: a widget's console is not attached
    /// to anything a development host can read, so the one place a run can leave a
    /// trace is the shared container, which `devicectl` can copy from. Written by
    /// the widget and read by a person; nothing in the app calls it.
    ///
    /// Cheap when nobody looks: one small append per timeline build, not per draw.
    /// It is not free, though — it is worth keeping only because it is the only
    /// window into a process with no console, and it found the bug that made
    /// Calendar draw as a grey symbol. See ``logByteLimit`` for the one bound on
    /// it.
    public static func diagnose(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        ) else { return }
        let directory = container.appending(path: "Library/Caches", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "direct-launch.log")
        let entry = Data(("[\(Date())] " + line() + "\n").utf8)

        // The whole rotation is done under one lock. Without it two threads racing
        // on a file at the limit could each *read* an over-limit size, and the
        // second `entry.write(…, .atomic)` would replace the file the first just
        // started appending to — losing its lines, and leaving the other append
        // pointed at a file that no longer exists. The window is small, and the
        // file is reached by two processes (app and extension) that do not share
        // this lock, so the cross-process case stays best-effort; what this
        // removes is the in-process race, which is the one that runs on every
        // render.
        Self.logLock.lock()
        defer { Self.logLock.unlock() }

        // Rotate by starting over. Keeping the tail instead would mean reading and
        // rewriting the whole file on the render path, for a log whose recent lines
        // are what a person reads anyway — the newest timeline is the one that
        // matters.
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int ?? 0
        if size > logByteLimit {
            try? entry.write(to: file, options: .atomic)
            return
        }

        if let handle = try? FileHandle(forWritingTo: file) {
            // `try?` on the write, then a plain close: closing a handle trimmed by
            // `seekToEndOfFile` on a shorter file would erase the lines written
            // after it, and a diagnostic that eats the very timeline it is meant to
            // record is worse than one that drops a line.
            handle.seekToEndOfFile()
            handle.write(entry)
            try? handle.close()
        } else {
            try? entry.write(to: file, options: .atomic)
        }
        #endif
    }

    /// Serialises ``diagnose(_:)``'s rotation check and append. See the comment
    /// there for the race it closes.
    private static let logLock = NSLock()

    // MARK: - Artwork validation

    /// A 256px image is enough for the largest icon drawn in the small widget.
    /// Decode from the source at this size rather than holding full-resolution
    /// images in the memory-limited extension. Bounds are checked before decoding.
    static let artworkPixelLimit = 256
    static let artworkByteLimit = 10 * 1_024 * 1_024
    static let artworkSourceSideLimit = 8_192
    private static let artworkSourcePixelLimit = 16_777_216

    static func artworkThumbnail(_ data: Data, maxPixelSize: Int = artworkPixelLimit) -> CGImage? {
        let pixelLimit = min(max(1, maxPixelSize), artworkPixelLimit)
        guard !data.isEmpty, data.count <= artworkByteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false,
              ] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              hasCompleteImageContainer(data, type: CGImageSourceGetType(source) as String?),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...artworkSourceSideLimit).contains(width),
              (1...artworkSourceSideLimit).contains(height),
              width * height <= artworkSourcePixelLimit,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelLimit,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              image.width <= pixelLimit, image.height <= pixelLimit
        else { return nil }
        return image
    }

    /// ImageIO deliberately recovers partial images; it can report a truncated
    /// PNG as complete and fill the missing pixels. Do not cache that recovery
    /// as the final app icon. Check PNG chunk boundaries/checksums and the JPEG
    /// end marker before asking the decoder for pixels.
    static func hasCompleteImageContainer(_ data: Data, type: String?) -> Bool {
        if type == UTType.jpeg.identifier {
            return data.count >= 2 && data.suffix(2).elementsEqual([0xFF, 0xD9])
        }
        guard type == UTType.png.identifier else { return true }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            func word(at offset: Int) -> UInt32 {
                UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
            }
            var offset = 8 // PNG signature, already recognized by ImageIO.
            while offset <= bytes.count - 12 {
                let length = Int(word(at: offset))
                guard length <= bytes.count - offset - 12 else { return false }
                var checksum = UInt32.max
                for index in (offset + 4)..<(offset + 8 + length) {
                    checksum = pngCRCTable[Int((checksum ^ UInt32(bytes[index])) & 0xFF)] ^ (checksum >> 8)
                }
                guard checksum ^ UInt32.max == word(at: offset + 8 + length) else { return false }
                let next = offset + length + 12
                if word(at: offset + 4) == 0x49454E44 { // IEND
                    return length == 0 && next == bytes.count
                }
                offset = next
            }
            return false
        }
    }

    private static let pngCRCTable: [UInt32] = (0..<256).map { byte in
        var value = UInt32(byte)
        for _ in 0..<8 {
            value = value & 1 == 0 ? value >> 1 : 0xEDB88320 ^ (value >> 1)
        }
        return value
    }

    /// HTTP success is not image success: an error page or truncated download
    /// must never become the durable cache entry. Re-encoding a decoded thumbnail
    /// also strips source metadata and gives every new cache entry a bounded size.
    static func normalizedArtwork(_ data: Data) -> Data? {
        guard let image = artworkThumbnail(data) else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            png, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return png as Data
    }

    /// Explicit choices query only their selected storefront and use a separate
    /// cache. Legacy mappings and automatic matching retain the API's default
    /// US storefront followed by China mainland. Neither path reads the user's
    /// Apple Account storefront or changes the system action being launched.
    static func fetch(appStoreID id: Int, country: String? = nil) async -> Data? {
        await fetch(appStoreID: id, country: country, load: request)
    }

    static func fetch(appStoreID id: Int, country: String? = nil, load: (URL) async -> Data?) async -> Data? {
        guard id > 0 else { return nil }
        let countries: [String?]
        if let country {
            guard let normalized = AppStoreCountry.normalized(country) else { return nil }
            countries = [normalized]
        } else {
            countries = [nil, "cn"]
        }
        for country in countries {
            guard !Task.isCancelled else { return nil }
            guard let url = AppStoreLookup.lookupURL(ids: [id], country: country),
                  let payload = await load(url),
                  !Task.isCancelled,
                  let artworkURL = AppStoreLookup.parse(payload).first(where: { $0.trackID == id })?.artworkURL.flatMap(URL.init(string:)),
                  let data = await load(artworkURL),
                  !Task.isCancelled,
                  let artwork = normalizedArtwork(data)
            else { continue }
            return artwork
        }
        return nil
    }
}
