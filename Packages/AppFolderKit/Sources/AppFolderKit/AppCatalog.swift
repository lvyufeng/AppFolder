import Foundation

/// Access to the app catalog defined in `AppCatalog+Data.swift`.
///
/// The data is kept in its own file because it is large, generated-ish, and
/// changes for reasons that have nothing to do with logic.
public enum AppCatalog {
    /// Catalogue entries whose App Store id has been cross-checked.
    ///
    /// Kept apart from ``all`` because the five 待验证 entries are guesses: name
    /// matching — ``match(name:)`` and ``search(_:)`` — draws from this pool, so
    /// a guess is never handed to a slot as though it were confirmed.
    public static var selectable: [KnownApp] {
        all.filter { $0.confidence == .verified }
    }

    /// The catalogue entry for an App Store id, if we have one.
    ///
    /// The hinge for icon lookup: a slot the system names is matched back to an
    /// entry, and the entry carries the App Store id whose artwork is cached.
    /// Matches on the App Store id rather than the name because the id is exact
    /// and the name is not — searching "Keep" returns three different apps, and
    /// matching by name would hand the user the wrong one's icon.
    public static func entry(appStoreID: Int) -> KnownApp? {
        all.first { $0.appStoreID == appStoreID }
    }

    /// The catalogue entry whose name is the one the system showed for an app.
    ///
    /// The system hands a direct-launch slot nothing but a display name — see
    /// ``DirectLaunchIcons`` — so resolving that name back to an entry is the only
    /// way to reach the App Store id that names the icon file. It is deliberately
    /// the *weaker* lookup: an exact match on either name wins, and anything short
    /// of that falls back to ``search(_:)``'s ranking rather than being rejected,
    /// because the two strings are written by different people — the system shows
    /// the app's own display name ("猫眼") and the catalogue stores the storefront
    /// name ("猫眼电影"), which are frequently not equal.
    ///
    /// A wrong answer here costs a wrong *icon*, never a wrong launch: the tap is
    /// still resolved by the system from the shortcut itself.
    public static func match(name: String) -> KnownApp? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        if let exact = all.first(where: {
            $0.name.lowercased() == needle || $0.englishName.lowercased() == needle
        }) {
            return exact
        }
        return search(name).first
    }

    /// Ranks exact name matches ahead of prefix matches ahead of substring
    /// matches, because the caller is matching the name of an app the user is
    /// looking at.
    public static func search(_ query: String) -> [KnownApp] {
        let pool = selectable
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return pool }

        func rank(_ app: KnownApp) -> Int? {
            let name = app.name.lowercased()
            let english = app.englishName.lowercased()

            if name == needle || english == needle { return 0 }
            if name.hasPrefix(needle) || english.hasPrefix(needle) { return 1 }
            if name.contains(needle) || english.contains(needle) { return 2 }
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
