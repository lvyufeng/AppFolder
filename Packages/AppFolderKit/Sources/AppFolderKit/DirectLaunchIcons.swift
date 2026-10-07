import Foundation

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
/// ## Why not `IconStore`
///
/// ``IconStore`` in the app target does the same dance but returns `UIImage`, which
/// this package cannot import, and it resolves *tiles* by App Store id. Here the
/// input is a name, and the caller is often the widget extension, which the app
/// target's type cannot reach. So the lookup lives here, on the plain types both
/// processes share.
public enum DirectLaunchIcons {
    /// Where artwork lives inside the App Group, same directory ``IconStore`` uses
    /// so the two never write two copies of one icon under two names.
    public static let directoryName = "Icons"

    /// What a slot resolved to, so the caller can draw it without asking again.
    public struct Resolved: Sendable, Equatable {
        public let name: String
        public let appStoreID: Int?
        public let symbolName: String?
    }

    /// Resolves the app behind a slot's display name and makes sure its icon is cached.
    ///
    /// - Parameter name: the display name the system showed, which is the app's own
    ///   name and not necessarily the storefront's.
    /// - Returns: the id and symbol to draw, after the artwork is on disk.
    public static func resolve(name: String) async -> Resolved {
        // The catalogue is tried first because it needs no request and answers
        // exactly; the App Store is the fallback that makes this work for the apps
        // the catalogue has never heard of.
        if let known = AppCatalog.match(name: name) {
            if let id = known.appStoreID {
                _ = await ensureIcon(appStoreID: id)
                return Resolved(name: name, appStoreID: known.appStoreID, symbolName: known.symbolName)
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
                        return Resolved(name: name, appStoreID: nil, symbolName: known.symbolName)
                    }
                    // Reads from disk when the artwork is already there, so this
                    // is not a network call — see ``ensureIcon(appStoreID:)``.
                    _ = await ensureIcon(appStoreID: id)
                    return Resolved(name: name, appStoreID: id, symbolName: known.symbolName)
                }
                if let id = await systemAppID(name: name, englishName: known.englishName) {
                    cacheSystemAppID(id, name: name)
                    _ = await ensureIcon(appStoreID: id)
                    return Resolved(name: name, appStoreID: id, symbolName: known.symbolName)
                }
            }
            return Resolved(name: name, appStoreID: nil, symbolName: known.symbolName)
        }

        guard let id = await searchAppStoreID(name: name) else {
            // Not found: cached as a miss (see ``markMiss(name:)``) so the next
            // timeline does not spend another request on the same unknown name.
            markMiss(name: name)
            return Resolved(name: name, appStoreID: nil, symbolName: nil)
        }
        _ = await ensureIcon(appStoreID: id)
        return Resolved(name: name, appStoreID: id, symbolName: nil)
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
    /// - Returns: `nil` when the store lists no `com.apple.*` app by either name,
    ///   which is the honest answer for the few system apps with no listing — the
    ///   caller then keeps its symbol.
    static func systemAppID(name: String, englishName: String?) async -> Int? {
        var tried: Set<String> = []
        for term in [name, englishName].compactMap({ $0 }) where tried.insert(term).inserted {
            // The device's own storefront first, then `cn`, matching
            // ``searchAppStoreID(name:)``: the first is where an installed app
            // lives, and the second is the answer for a device whose storefront
            // does not carry a Chinese system app's listing.
            for country in [nil, "cn"] as [String?] {
                guard let url = AppStoreLookup.searchURL(term: term, country: country, limit: 6),
                      let (payload, _) = try? await URLSession.shared.data(from: url),
                      let id = appleAppID(payload: payload)
                else { continue }
                return id
            }
        }
        return nil
    }

    /// The first row in a search response that is unambiguously Apple's, or `nil`.
    ///
    /// Keyed on `com.apple.` alone, deliberately. Requiring the seller name as
    /// well would be redundancy rather than caution — the seller string differs by
    /// storefront (`Apple Inc.` here, `Apple Distribution International` in `cn`)
    /// while the bundle prefix does not — and a second condition can only reject
    /// correct rows, never admit a wrong one.
    ///
    /// The bundle id is checked rather than the name for the same reason: a name
    /// match is what the ordinary matcher already does, and its failure on exactly
    /// these apps is the bug this exists to fix.
    static func appleAppID(payload: Data) -> Int? {
        AppStoreLookup.parse(payload)
            .first { $0.bundleID?.hasPrefix("com.apple.") == true }?
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

    private static func systemAppCacheURL(name: String) -> URL? {
        containerDirectory()?.appending(path: "system-v1-\(stableHash(name)).txt")
    }

    /// The App Store id for an app, by name, or `nil` if the store cannot name it.
    ///
    /// Two storefronts are tried, the device's own first and `cn` second. The
    /// second is not a guess at the user's region — it is the answer for the case
    /// this widget exists to serve: a Chinese app whose *display* name is its
    /// English one ("Alimail"), which the device's storefront does not match but a
    /// Chinese storefront does.
    static func searchAppStoreID(name: String) async -> Int? {
        guard let deviceURL = AppStoreLookup.searchURL(term: name, country: nil, limit: 5) else {
            return nil
        }
        if let id = await bestMatch(url: deviceURL, name: name) { return id }

        guard let cnURL = AppStoreLookup.searchURL(term: name, country: "cn", limit: 5) else {
            return nil
        }
        return await bestMatch(url: cnURL, name: name)
    }

    /// The result that actually is the app asked about, or `nil`.
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
    static func bestMatch(url: URL, name: String) async -> Int? {
        guard let (payload, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return bestMatch(payload: payload, name: name)
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
        // correct answer away. Shortest match wins, on the theory that the app whose
        // name is closest to the display name is where the display name came from.
        let containing = rows
            .filter { normalized($0.name).contains(needle) }
            .min { normalized($0.name).count < normalized($1.name).count }
        if let containing { return containing.trackID }

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
    static func ensureIcon(appStoreID id: Int) async -> Data? {
        if let cached = read(id: id) { return cached }
        guard let data = await fetch(appStoreID: id) else { return nil }
        write(id: id, data: data)
        return data
    }

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

    /// The file name an icon is cached under, mirroring ``IconStore``'s scheme so
    /// the two stores agree on where a given app's artwork lives.
    public static func fileName(appStoreID: Int) -> String { "\(appStoreID).png" }

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
    private static let missVersion = 3

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

    /// Appends one line to a log in the App Group's `Library/Caches`.
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
    public static func diagnose(_ line: String) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        ) else { return }
        let directory = container.appending(path: "Library/Caches", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "direct-launch.log")
        let entry = Data(("[\(Date())] " + line + "\n").utf8)

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
            handle.seekToEndOfFile()
            handle.write(entry)
            try? handle.close()
        } else {
            try? entry.write(to: file, options: .atomic)
        }
    }

    // MARK: - Files

    private static func read(id: Int) -> Data? {
        guard let directory = containerDirectory() else { return nil }
        return try? Data(contentsOf: directory.appending(path: fileName(appStoreID: id)))
    }

    private static func write(id: Int, data: Data) {
        guard let directory = containerDirectory() else { return }
        try? data.write(to: directory.appending(path: fileName(appStoreID: id)), options: .atomic)
    }

    /// The artwork for one id, one request.
    ///
    /// No `country` parameter, so the request resolves to the device's own
    /// storefront — right for an app that is installed here, and the reason the
    /// full ``AppStoreRegions/lookupOrder`` sweep is not needed: the search that
    /// found the id has already established which storefront carries the app.
    static func fetch(appStoreID id: Int) async -> Data? {
        guard let url = AppStoreLookup.lookupURL(ids: [id]) else { return nil }
        guard let (payload, _) = try? await URLSession.shared.data(from: url),
              let first = AppStoreLookup.parse(payload).first,
              let artworkURL = first.artworkURL.flatMap(URL.init(string:))
        else { return nil }
        return try? await URLSession.shared.data(from: artworkURL).0
    }
}