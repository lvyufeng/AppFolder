import Foundation

/// Access to the app catalog defined in `AppCatalog+Data.swift`.
///
/// The data is kept in its own file because it is large, generated-ish, and
/// changes for reasons that have nothing to do with logic.
public enum AppCatalog {
    /// Entries safe to show in the picker by default.
    public static var selectable: [KnownApp] {
        all.filter { $0.confidence == .verified }
    }

    /// Every scheme to declare in `LSApplicationQueriesSchemes`.
    ///
    /// Only ``selectable`` entries, because the array has a hard cap — Apple
    /// documents 50 entries for apps linked against iOS 15, and 25 for apps
    /// linked against iOS 27:
    ///
    /// > Apps linked on or after iOS 15 are limited to a maximum of 50 entries
    /// > in the `LSApplicationQueriesSchemes` key. Apps linked on or after
    /// > iOS 27 are limited to a maximum of 25 entries…
    ///
    /// So this list is a budget, not a catalogue. Note the asymmetry it takes
    /// advantage of: `canOpenURL` is capped, but `open(_:)` is not —
    ///
    /// > Unlike this method, the `open(_:options:completionHandler:)` method
    /// > isn't constrained by the `LSApplicationQueriesSchemes` requirement.
    ///
    /// — which means a tile for an app *not* in this list can still be opened.
    /// The cap costs us the ability to *detect* an app, never the ability to
    /// launch one.
    public static var queriedSchemes: [String] {
        var seen: Set<String> = []
        return selectable
            .map(\.scheme)
            .filter { seen.insert($0).inserted }
    }

    /// The entries worth spending the query budget on, most valuable first.
    ///
    /// The picker does not depend on this: it lists the whole catalogue, and the
    /// user can add any of it. What it changes is which apps the picker can label
    /// "已安装", so it is ordered by how likely a user is to have the app and to
    /// look for it here.
    public static var priorityForQuery: [KnownApp] {
        selectable.filter { $0.appStoreID != nil }
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
