import Foundation

/// Repairs tiles that were saved in a state the widget cannot launch.
///
/// This exists because of a shipped bug. 地图 was configured as 直接打开 while its
/// only URL was `maps://`. `OpenLinkIntent` refuses custom schemes, so
/// `TileButton` fell through to the inert branch: the tile drew, the tap did
/// nothing, and there was no error anywhere to look at. The user's report —
/// "点击之后会进入 app 而不是直接打开" — was the only symptom, and it took reading
/// the stored library to find the cause.
///
/// Two repairs, in this order:
///
/// 1. **Backfill the link.** A tile created before the catalogue knew an app's
///    universal link has no way to acquire one afterwards, because the catalogue
///    is not consulted again after the tile is made.
/// 2. **Repair the route.** A tile whose strategy cannot launch at all in a
///    folder grid — 系统快捷启动, or 直接打开 with no link — is moved to one that
///    can. This overrides a stored user choice, which needs justifying: the
///    choice is not a preference, it is a setting that provably does nothing in
///    this context, and silently keeping it is what produced the bug. The editor
///    offers the same repair by hand; this is that button, applied to libraries
///    that were saved before it existed.
///
/// Applied on read rather than as a one-shot migration behind a version number,
/// because it is idempotent and cheap, and because the condition it fixes is not
/// really about schema versions: a tile can fall into it any time the catalogue
/// learns or loses a link. Running it on every load means the widget and the app
/// always agree, and there is no "upgraded" flag that can be wrong.
///
/// ## A migration that was here and was removed
///
/// A third repair briefly lived here: flagging tiles whose scheme had been
/// *guessed*, so the widget could withhold them until the user confirmed one. It
/// is gone, and the reason is worth keeping because the idea is tempting.
///
/// It was justified as "a tile that opens nothing is worse than an absent one",
/// which sounds right and is not. Withholding is a failure the user cannot
/// diagnose — a working app simply vanishes from the Home Screen — while a wrong
/// guess is loud: the tap raises the 打不开 alert, and the editor lists the
/// alternatives one tap away. That trade is the point, and it does not depend on
/// the guesser being right very often.
///
/// The example 票牛 used to be given here was wrong and is worth correcting rather
/// than deleting. It claimed `pner://` was 票牛's real scheme, hidden by this rule
/// for no reason. Measured on the device, `pner://` is *not* a scheme 票牛
/// registers — `piaoniu://` is — so the tile it produced opened nothing, and the
/// guesser was simply wrong about this app. The rule above still stands: the
/// answer is to fix the guess and make its failure visible, which is now the case
/// on both counts (see the catalogue entry), not to hide the tile.
///
/// The lesson generalises: withhold a tile only for something that makes it
/// *undrawable* (no artwork — a blank square with a label). Never for a property
/// that only affects what happens when it is tapped, because that trade always
/// removes something visible to prevent something already visible.
public enum LibraryRepair {
    /// Returns a library whose tiles can all be launched by the widget.
    public static func repair(_ library: FolderLibrary) -> FolderLibrary {
        var library = library

        for folderIndex in library.folders.indices {
            for tileIndex in library.folders[folderIndex].tiles.indices {
                var tile = library.folders[folderIndex].tiles[tileIndex]

                // 1. Replace a scheme the catalogue disagrees with.
                //
                // ``FolderTile/urlString`` is otherwise the tile's business —
                // the user may have edited it, and this file's rule is to leave
                // edits alone. The scheme of an app tile is the exception, and
                // the reason is that it is not a preference but a fact: a
                // catalogue entry and a tile that disagree about 票牛's scheme
                // are not two reasonable opinions, one of them is wrong.
                //
                // 票牛 is the case that produced this rule. Tiles in the wild
                // carry `pner://` — the bundle id (`com.ipiaoniu.pner`) makes it
                // the obvious guess and the app registers it nowhere. Measured
                // on the device, `pner://` cannot be opened and `piaoniu://`
                // can. Fixing the catalogue entry does nothing for those tiles
                // on its own, because the catalogue is not consulted again after
                // a tile is made; this is what consults it.
                //
                // What makes it safe is the *identification*, never the comparison, and
                // the identification has to be by id. ``catalogID`` is the app
                // telling us which entry it made this tile from, so rewriting the
                // scheme is the app correcting its own earlier answer.
                //
                // It deliberately does **not** go through ``catalogEntry(for:)``,
                // whose name-and-scheme fallback exists for backfill. That
                // fallback can't match a wrong-scheme tile anyway — the scheme is
                // the part that's wrong — and widening it enough to try would
                // make a tile the user named 地图 eligible for rewriting, which
                // is the thing this file promises never to do. A repair that
                // changes what a tap *does* may only act on id.
                //
                // The cost is that a tile with no `catalogID` keeps its wrong
                // scheme, as the user's own 票牛 tiles do. That is the honest
                // limit of the repair, and the `catalogID: String?` on
                // ``FolderTile`` is what makes the next one repairable — it is
                // present on every tile the catalogue made.
                if let catalogID = tile.catalogID,
                   let app = AppCatalog.all.first(where: { $0.id == catalogID }),
                   !app.scheme.isEmpty,
                   app.scheme != tile.urlString {
                    tile.urlString = app.scheme
                }

                // 2. Backfill, but never overwrite: a tile's stored link may have
                // been edited, and the tile is the authority on itself.
                if tile.universalLink == nil, let app = catalogEntry(for: tile) {
                    tile.universalLinkString = app.universalLink
                }

                // 2. Keep the stored route in step with the derived one.
                //
                // The route is no longer a user setting — see
                // ``FolderTile/launchRoute`` — so the stored value is only still
                // written for a build that reads it. Keeping it in sync here means
                // a library written before this change, or by a build that still
                // had the picker, converges on the same answer the widget derives.
                //
                // Only ever set, never cleared: a tile with neither a link nor a
                // URL keeps whatever it had, because there is no better value and
                // overwriting it would destroy the record of what the user once
                // chose.
                if tile.url != nil || tile.universalLink != nil {
                    tile.strategy = tile.launchRoute
                }

                library.folders[folderIndex].tiles[tileIndex] = tile
            }
        }

        return library
    }

    /// The catalogue entry a tile came from, by id and then by appearance.
    ///
    /// ``FolderTile/catalogID`` is the honest answer and the one to prefer, but
    /// it is absent on every tile made before the entry existed — including, on
    /// the library that prompted this file, a hand-added 地图. Falling back to
    /// *name plus exact scheme* recovers those: both have to match a single
    /// catalogue entry, which is a much stronger claim than a name alone, and the
    /// only thing the match is used for is filling in a field that is `nil`.
    ///
    /// That last clause is why the `nil` case can afford to be this loose, and
    /// why the scheme replacement above **cannot** use this lookup. Matching on
    /// a name would mean a tile the user made and named 地图 is eligible to have
    /// its scheme rewritten, which is the one thing this file promises not to do.
    /// A repair may only rewrite what it can identify by id — see the scheme
    /// replacement, which deliberately reads ``FolderTile/catalogID`` directly
    /// instead of coming through here.
    ///
    /// Ambiguity is resolved by refusing to guess. Two entries sharing a title
    /// and a scheme would be a catalogue bug, and picking either one would paper
    /// over it.
    private static func catalogEntry(for tile: FolderTile) -> KnownApp? {
        if let catalogID = tile.catalogID {
            return AppCatalog.all.first { $0.id == catalogID }
        }

        let matches = AppCatalog.all.filter { app in
            app.scheme == tile.urlString
                && (app.name == tile.title || app.englishName == tile.title)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
