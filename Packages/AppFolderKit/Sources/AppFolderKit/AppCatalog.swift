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
    /// The cap is a *declaration* cap, not a runtime one — measured, not assumed.
    /// Declaring 57 schemes and probing all 57 worked; declaring 27 and probing a
    /// name that wasn't among them did not. See ``queriedSchemes`` for what that
    /// means and why this stays at 25 anyway.
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
    /// Measured on iOS 27 against a purpose-built app registering `afprobe1`:
    ///
    /// | declared? | handler exists? | `canOpenURL` |
    /// |---|---|---|
    /// | yes | yes | `true` |
    /// | yes | no | `false` |
    /// | no | yes | `false` |
    /// | no | no | `false` |
    ///
    /// The third row is the one that matters. `maps://` and `shortcuts://` came
    /// back `true` only because they are declared; the same was true for the
    /// probe app's scheme only while it was declared. There is no free lunch in
    /// the undeclared case, which is why this list has to stay curated and
    /// budgeted rather than attempted wholesale.
    ///
    /// (One incidental finding from the same experiment: this cap is not enforced
    /// by rejecting the over-budget entries. A build declaring 57 schemes probed
    /// all 57 successfully, including ones at positions 56 and 57. The limit
    /// Apple documents is real but not applied at that layer, at least on the
    /// simulator — so the budget here is a cautious reading of the rule, not a
    /// wall we ran into.)
    public static var queriedSchemes: [String] {
        var seen: Set<String> = []
        return all
            .filter { $0.confidence == .verified && $0.appStoreID != nil }
            .prefix(queryBudget)
            .map(\.scheme)
            .filter { seen.insert($0).inserted }
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
