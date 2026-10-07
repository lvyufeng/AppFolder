import Foundation
import Testing

@testable import AppFolderKit

/// The picker's selection, and the two bugs it was extracted to fix.
///
/// Both are regressions with a specific corpse behind them:
///
/// 1. Adding an app by hand called the screen's own exit with `[tile]` instead of
///    adding to the selection, so it **replaced the folder's whole contents**.
/// 2. Resolving always put hand-built tiles first and catalogue entries after, so
///    opening the picker and tapping 完成 without touching anything **rearranged
///    the folder** — and the widget's grid is positional, so that is a visible
///    change to the Home Screen.
@Suite("Tile selection")
struct TileSelectionTests {
    private func manualTile(_ title: String, scheme: String = "custom://") -> FolderTile {
        FolderTile(title: title, urlString: scheme, bundleID: "com.example.thing")
    }

    private func titles(_ tiles: [FolderTile]) -> [String] { tiles.map(\.title) }

    // MARK: - Bug 1: adding must not replace

    /// The whole first bug in one assertion: a folder holding an app, plus one
    /// hand-added app, must hold **two** apps.
    @Test("Adding a hand-built tile keeps what was already selected")
    func addingDoesNotReplaceTheSelection() throws {
        let wechat = try #require(AppCatalog.all.first { $0.id == "wechat" })

        var selection = TileSelection(catalogIDs: ["wechat"])
        selection.add(manualTile("保持"))

        let resolved = selection.resolved
        #expect(resolved.count == 2)
        #expect(titles(resolved).contains("微信"))
        #expect(titles(resolved).contains("保持"))
        #expect(resolved.contains { $0.catalogID == wechat.id })
    }

    /// The case the bug was *invisible* in, because `[tile]` is the correct answer
    /// for an empty folder — which is why it shipped.
    @Test("Adding to an empty selection yields exactly that tile")
    func addingToNothingIsJustThatTile() {
        var selection = TileSelection()
        selection.add(manualTile("第一个"))

        #expect(titles(selection.resolved) == ["第一个"])
    }

    /// ``TileSelection/add(_:)`` routes a catalogue-backed tile into a reference
    /// rather than a copy, so the two shapes can never hold the same app twice.
    @Test("Adding a catalogue-backed tile does not duplicate it")
    func addingACatalogueTileDeduplicates() {
        var selection = TileSelection(catalogIDs: ["wechat"])
        selection.add(FolderTile(app: AppCatalog.all[0]))

        #expect(selection.catalogIDs == ["wechat", AppCatalog.all[0].id])
        #expect(selection.extraTiles.isEmpty)
        #expect(selection.resolved.filter { $0.catalogID == "wechat" }.count == 1)
    }

    /// Ticking the same row twice is one entry, not two.
    @Test("Ticking an already-ticked entry is idempotent", arguments: [true, true, false, true])
    func tickingIsIdempotent(tick: Bool) {
        var selection = TileSelection()
        selection.setCatalog("wechat", isSelected: true)
        selection.setCatalog("wechat", isSelected: tick)

        #expect(selection.catalogIDs == (tick ? ["wechat"] : []))
        #expect(selection.entries.count == (tick ? 1 : 0))
    }

    // MARK: - Bug 2: order must survive a round trip

    /// Interleaved contents come back interleaved. This is the property that makes
    /// opening the picker and hitting 完成 a no-op.
    @Test("Seeding then resolving preserves the folder's own order")
    func roundTripIsStable() {
        let tiles = [
            manualTile("甲"),
            FolderTile(app: AppCatalog.all[0]),
            manualTile("乙"),
            FolderTile(app: AppCatalog.all[1]),
            manualTile("丙"),
        ]

        #expect(titles(TileSelection.seeded(from: tiles).resolved) == titles(tiles))
    }

    /// A newly ticked entry lands at the end, where the user can see it go —
    /// not at a position decided by the catalogue's own ordering.
    @Test("A newly ticked entry is appended, not sorted into place")
    func newEntriesAppend() throws {
        // Deliberately a catalogue entry that sorts *first* in the catalogue, so
        // an implementation that used catalogue order would put it in front.
        let first = try #require(AppCatalog.all.first)
        var selection = TileSelection.seeded(from: [manualTile("甲")])

        selection.setCatalog(first.id, isSelected: true)

        #expect(titles(selection.resolved) == ["甲", first.name])
    }

    /// Hand-built tiles keep the order they were added in. The grid is positional,
    /// so a reordering here is a folder that rearranges itself.
    @Test("Hand-built tiles keep the order they were added in")
    func handBuiltTilesKeepOrder() {
        var selection = TileSelection()
        selection.add(manualTile("一"))
        selection.add(manualTile("二"))
        selection.add(manualTile("三"))

        #expect(titles(selection.resolved) == ["一", "二", "三"])
    }

    // MARK: - Identity

    /// ``TileSelection/seeded(from:)`` splits on the catalogue id and nothing else
    /// — the same rule ``LibraryRepair`` uses, and for the same reason.
    @Test("Seeding splits on the catalogue id, not on the name")
    func seedingSplitsOnIdentity() {
        let catalogue = FolderTile(app: AppCatalog.all[0])
        // A user's own tile that happens to share the catalogue's display name.
        // Matching by name would adopt it and rewrite its scheme with the
        // catalogue's — the mistake an earlier LibraryRepair change made, and the
        // existing tests rejected.
        let byName = FolderTile(title: AppCatalog.all[0].name, urlString: "mine://")

        let selection = TileSelection.seeded(from: [catalogue, byName])

        #expect(selection.catalogIDs == [AppCatalog.all[0].id])
        #expect(titles(selection.extraTiles) == [byName.title])
    }

    /// A hand-built tile carries a scheme that exists nowhere else, so it has to
    /// survive resolution byte for byte — including the bundle id, which is the
    /// only record of ``SchemeGuess``'s input.
    @Test("A hand-built tile survives resolution unchanged")
    func handBuiltTilesAreUntouched() throws {
        let original = manualTile("冷门 App", scheme: "obscure://open")
        let resolved = try #require(TileSelection.seeded(from: [original]).resolved.first)

        #expect(resolved == original)
        #expect(resolved.bundleID == "com.example.thing")
    }

    /// Resolving rebuilds catalogue tiles from the catalogue, so a correction that
    /// landed since the folder was assembled reaches it.
    @Test("A catalogue tile is rebuilt from the catalogue, not from the stored copy")
    func resolvedTilesComeFromTheCatalogue() throws {
        let entry = try #require(AppCatalog.all.first { $0.id == "piaoniu" })
        let stale = FolderTile(title: entry.name, urlString: "pner://", catalogID: entry.id)

        let tile = try #require(TileSelection.seeded(from: [stale]).resolved.first)

        #expect(tile.urlString == entry.scheme)
        #expect(tile.urlString != "pner://")
    }

    /// A reference the catalogue no longer holds is dropped rather than drawn as a
    /// nameless blank the user cannot explain.
    @Test("A catalogue reference that no longer resolves is dropped")
    func vanishedCatalogueEntriesAreDropped() {
        var selection = TileSelection(catalogIDs: ["wechat"])
        selection.setCatalog("an-app-that-was-removed", isSelected: true)

        #expect(titles(selection.resolved) == ["微信"])
    }

    // MARK: - Emptiness and removal

    /// ``TileSelection/isEmpty`` is what lets the screen say "you removed
    /// everything" rather than "this folder was already empty".
    @Test("Emptiness accounts for every kind of entry")
    func emptinessCoversBothKinds() {
        #expect(TileSelection().isEmpty)
        #expect(!TileSelection(catalogIDs: ["wechat"]).isEmpty)
        #expect(!TileSelection(extraTiles: [manualTile("x")]).isEmpty)
    }

    /// An empty selection resolves to an empty folder rather than to the whole
    /// catalogue — the failure mode if a reference list were ever given an "empty
    /// means everything" reading.
    @Test("An empty selection resolves to nothing, not to everything")
    func emptyResolvesToEmpty() {
        #expect(TileSelection().resolved.isEmpty)
        #expect(TileSelection.seeded(from: []).resolved.isEmpty)
    }

    /// Removing the last hand-built tile leaves the catalogue half alone.
    @Test("Removing a hand-built tile leaves the rest standing")
    func removingOneLeavesTheOthers() throws {
        var selection = TileSelection.seeded(from: [manualTile("删我"), manualTile("留我")])
        let doomed = try #require(selection.extraTiles.first)

        selection.removeTile(id: doomed.id)

        #expect(titles(selection.resolved) == ["留我"])
    }

    /// Unticking a row removes it from wherever it sits, not just from the end.
    @Test("Unticking removes the entry from its position")
    func untickingRemovesInPlace() throws {
        let tiles = [
            FolderTile(app: AppCatalog.all[0]),
            manualTile("中间"),
            FolderTile(app: AppCatalog.all[1]),
        ]
        var selection = TileSelection.seeded(from: tiles)

        selection.setCatalog(AppCatalog.all[0].id, isSelected: false)

        #expect(titles(selection.resolved) == ["中间", AppCatalog.all[1].name])
    }
}