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
/// which sounds right and is not. The guesser is correct most of the time — 票牛's
/// `pner://` is its real scheme and was hidden by this rule for no reason — so the
/// cost was working apps vanishing from the Home Screen, which is a failure the
/// user cannot even diagnose. A wrong guess, by contrast, is loud: the tap raises
/// the 打不开 alert, and the editor lists the alternatives one tap away.
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

                // 1. Backfill, but never overwrite: a tile's stored link may have
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
