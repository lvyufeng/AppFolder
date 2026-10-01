import Foundation

/// Access to the app catalog defined in `AppCatalog+Data.swift`.
///
/// The data is kept in its own file because it is large, generated-ish, and
/// changes for reasons that have nothing to do with logic.
public enum AppCatalog {
    /// How many schemes can be declared in `LSApplicationQueriesSchemes`.
    ///
    /// Apple documents the cap twice over:
    ///
    /// > Apps linked on or after iOS 15 are limited to a maximum of 50 entries in
    /// > the `LSApplicationQueriesSchemes` key. Apps linked on or after iOS 27 are
    /// > limited to a maximum of 25 entries in the `LSApplicationQueriesSchemes`
    /// > key.
    ///
    /// We link against iOS 27, so 25 is the number that applies.
    ///
    /// The cap is enforced at runtime, and it counts *honored* schemes, not just
    /// declarations — measured on iOS 27.0.1 on device, not assumed. A build
    /// declaring 133 valid schemes was asked about all 133: positions 1–25 were
    /// answered, and every one after them came back
    /// `"This app is not allowed to query for scheme …"`. 133 − 108 rejected = 25.
    ///
    /// So the cap is real and this number is a hard wall. An earlier note here
    /// recorded the opposite — that a 57-scheme build had probed all 57 — but
    /// that was measured on the simulator, which does not enforce the limit. The
    /// device does. See ``queriedSchemes`` for why the list is curated rather
    /// than merely truncated.
    public static let queryBudget = 25

    /// Entries safe to show in the picker by default.
    public static var selectable: [KnownApp] {
        all.filter { $0.confidence == .verified }
    }

    /// The schemes to declare in `LSApplicationQueriesSchemes`, exactly filling
    /// ``queryBudget``.
    ///
    /// The catalogue's own order *is* the priority order — Chinese apps first,
    /// most-installed first — so this is a prefix rather than a separate ranking.
    /// Entries without an App Store id are skipped: they have no artwork to
    /// fetch, so there is nothing for an install check to improve.
    ///
    /// Falling off the end is a small loss, not a broken app: `open(_:)` is
    /// exempt from the cap, so a tile for an unprobed app still opens. It just
    /// never earns the "已安装" label.
    ///
    /// `--check` in the `appfolder-schemes` tool fails if this list and the app's
    /// Info.plist disagree.
    ///
    /// ## What the cap actually constrains
    ///
    /// `canOpenURL` answers `false` for any scheme that is not declared, whether
    /// or not something handles it — and that rule is what makes the declaration
    /// list the discovery mechanism rather than a permission.
    ///
    /// Measured on iOS 27 against a purpose-built app registering `afprobe1`, and
    /// against system apps:
    ///
    /// | declared? | handler | kind | `canOpenURL` |
    /// |---|---|---|---|
    /// | yes | yes | third-party | `true` |
    /// | yes | no | — | `false` |
    /// | no | yes | third-party (`afprobe1`) | `false` |
    /// | no | yes | Apple's own (`x-apple-health://`, `sms://`) | **`true`** |
    /// | no | no | — | `false` |
    ///
    /// Two conclusions, and they point in opposite directions:
    ///
    /// * For **third-party** apps there is no free lunch. An app that was
    ///   genuinely installed came back `false` because its scheme was not
    ///   declared. Discovery requires declaration, which is why this list has to
    ///   stay curated and budgeted rather than attempted wholesale.
    /// * For **Apple's own** apps the declaration requirement is not enforced at
    ///   all. `x-apple-health://`, `sms://`, `maps://`, `App-prefs://` and
    ///   `photos-redirect://` all answered `true` while undeclared, because
    ///   Apple's apps ship in a privileged trust class. So brand-new iPhone
    ///   owners — the people whose Home Screen is nothing but system apps — can
    ///   have their apps detected without spending any of the budget.
    ///
    /// (A note on how the cap is enforced, from the device measurement behind
    /// ``queryBudget``: it does **not** reject the overflow with an error at
    /// launch, and it does not fail the build. It simply answers the first 25
    /// declarations and refuses the rest, per call, at the moment `canOpenURL`
    /// runs. That is the dangerous shape — the app launches, the sweep completes,
    /// and the only symptom is that the apps past position 25 are quietly
    /// reported 未安装. There is nothing to catch; the list has to be right.)
    public static var queriedSchemes: [String] {
        var seen: Set<String> = []
        return all
            .filter { $0.confidence == .verified && $0.appStoreID != nil }
            .prefix(queryBudget)
            .map(\.scheme)
            .filter { seen.insert($0).inserted }
    }

    /// Every scheme the probe should ask about, declared or not.
    ///
    /// Wider than ``queriedSchemes`` by exactly one group: Apple's own apps. They
    /// answer `canOpenURL` without being declared, so declaring them would burn
    /// budget slots to buy nothing. They are appended rather than filtered in, so
    /// the declared prefix keeps its ranking and this stays a strict superset.
    ///
    /// Anything *not* in `queriedSchemes` and not a system app is unprobeable and
    /// will come back unknown — which is what ``InstallationProber/status(of:)``
    /// reports it as, rather than claiming it is absent.
    public static var probeableSchemes: [String] {
        var seen: Set<String> = []
        return (queriedSchemes + all.filter(\.isSystemApp).map(\.scheme) + declaredSchemes)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// Every scheme the app actually declares in its `Info.plist`, in declaration
    /// order.
    ///
    /// Read from the bundle rather than assumed to equal ``queriedSchemes``,
    /// because the two can differ and the difference is dangerous in one
    /// direction: a scheme that is declared but never probed is a wasted
    /// declaration, while a scheme that is probed but not declared always reports
    /// `false` — so an app the user has installed is labelled 未安装, which is
    /// exactly the kind of confident wrong answer this whole file exists to avoid.
    ///
    /// Deriving the probe list from the declaration list makes that impossible by
    /// construction, and it is what lets the declaration list be widened without
    /// a matching code change.
    ///
    /// Empty when there is no bundle plist (the test host, a command-line tool),
    /// which is why the other two terms above stay.
    public static var declaredSchemes: [String] {
        guard
            let declared = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        else { return [] }
        return declared.map { "\($0)://" }
    }

    /// Whether the catalogue fits in the query budget, and what happens if not.
    ///
    /// Surfaced rather than asserted because the cap is a platform rule that
    /// changes between OS versions, and silently truncating a list is the kind of
    /// thing that goes unnoticed for months.
    public static var queryBudgetReport: (used: Int, budget: Int, overflow: [KnownApp]) {
        let eligible = all.filter { $0.confidence == .verified && $0.appStoreID != nil }
        return (min(eligible.count, queryBudget), queryBudget, Array(eligible.dropFirst(queryBudget)))
    }

    /// Entries matching a free-text query, best matches first.
    ///
    /// Ranks exact name matches ahead of prefix matches ahead of substring
    /// matches, because the picker is used by typing the name of an app the user
    /// is looking at on their Home Screen.
    /// The catalogue entry for an App Store id, if we have one.
    ///
    /// ## Why this is the hinge the whole feature turns on
    ///
    /// A user who finds their app through App Store search has an App Store id
    /// and nothing else — no scheme, and no way to discover one. But if the
    /// catalogue already holds that app, this returns its entry, and the entry
    /// carries a **verified** scheme. The user gets a working tile without ever
    /// learning what a URL scheme is.
    ///
    /// That makes catalogue size a direct measure of how often the user is asked
    /// to do something hard: every app added here is one fewer trip through
    /// ``SchemeGuess`` and the "试一下" flow. It is the reason "扩大目录" is worth
    /// doing as a separate, continuing effort rather than a one-off.
    ///
    /// Matches on the App Store id rather than the name because the id is exact
    /// and the name is not — searching "Keep" returns three different apps, and
    /// matching by name would hand the user the wrong one's scheme.
    public static func entry(appStoreID: Int) -> KnownApp? {
        all.first { $0.appStoreID == appStoreID }
    }

    public static func search(_ query: String, includeUnverified: Bool = false) -> [KnownApp] {
        let pool = includeUnverified ? all : selectable
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return pool }

        func rank(_ app: KnownApp) -> Int? {
            let name = app.name.lowercased()
            let english = app.englishName.lowercased()
            let scheme = app.schemeName.lowercased()

            if name == needle || english == needle { return 0 }
            if name.hasPrefix(needle) || english.hasPrefix(needle) { return 1 }
            if name.contains(needle) || english.contains(needle) { return 2 }
            if scheme.hasPrefix(needle) { return 3 }
            return nil
        }

        // Spell the tuple out: leaving it inferred makes the chained
        // `compactMap`/`sorted`/`map` a type-checker cliff.
        let ranked: [(app: KnownApp, rank: Int)] = pool.compactMap { app in
            guard let rank = rank(app) else { return nil }
            return (app, rank)
        }

        return ranked
            .sorted { lhs, rhs in
                lhs.rank == rhs.rank ? lhs.app.name < rhs.app.name : lhs.rank < rhs.rank
            }
            .map(\.app)
    }
}
