import Foundation
import Testing

@testable import AppFolderKit

/// The repair pass that runs on every library load.
///
/// The case that motivates all of this is real and was shipped: 地图 stored as
/// `strategy=universalLink` with `urlString=maps://` and no link. Nothing threw,
/// nothing logged — the widget drew the tile and the tap did nothing.
@Suite("Library repair")
struct LibraryRepairTests {
    /// A library holding one tile, in the shape the caller describes.
    private func library(_ tile: FolderTile) -> FolderLibrary {
        FolderLibrary(folders: [Folder(name: "常用", tiles: [tile])])
    }

    private func onlyTile(_ library: FolderLibrary) throws -> FolderTile {
        try #require(library.folders.first?.tiles.first)
    }

    /// The guarantee that makes it safe to let users add apps the catalogue has
/// never heard of.
///
/// ``LibraryRepair`` rewrites tiles that cannot launch, and it decides which
/// catalogue entry a tile belongs to. A hand-added tile has no `catalogID` and a
/// scheme no entry shares, so the entry lookup returns nothing — and the repair
/// must then leave the tile completely alone rather than "fixing" it toward a
/// route it cannot support.
    ///
    /// The failure this prevents is silent and total: every user-added app in
    /// every folder would be rewritten on the next launch, and because the repair
    /// runs on read, there would be nothing on disk to point at afterwards.
    @Test("A hand-added tile the catalogue does not know is left untouched")
    func userAddedTilesSurviveRepair() throws {
        let added = FolderTile(
            title: "Keep",
            scheme: "gotokeep://",
            appStoreID: 952694580
        )
        #expect(added.catalogID == nil)

        let tile = try onlyTile(LibraryRepair.repair(library(added)))

        #expect(tile.title == "Keep")
        #expect(tile.urlString == "gotokeep://")
        #expect(tile.appStoreID == 952694580)
        // No entry matched, so nothing was backfilled — and the user's own route
        // stands, because it can launch.
        #expect(tile.universalLinkString == nil)
        #expect(tile.strategy == .bounce)
        #expect(tile.canLaunch)
    }

    /// The same protection for a hand-added tile whose scheme happens to collide
    /// with a catalogue entry's *name*. The lookup falls back to name-plus-scheme
    /// matching, and a user typing a name onto a scheme they guessed wrong is the
    /// exact case where that fallback could misfire.
    @Test("A hand-added tile with a scheme no entry shares is not adopted")
    func userAddedTileIsNotAdoptedByName() throws {
        let added = FolderTile(title: "地图", scheme: "mycustom://", appStoreID: nil)
        let tile = try onlyTile(LibraryRepair.repair(library(added)))

        #expect(tile.urlString == "mycustom://")
        #expect(tile.universalLinkString == nil)
        #expect(tile.strategy == .bounce)
    }

    @Test("A universal link tile with no link falls back to a route that works")
    func repairsTheShippedBug() throws {
        let broken = FolderTile(
            title: "地图",
            urlString: "maps://",
            catalogID: "maps",
            strategy: .universalLink
        )
        let tile = try onlyTile(LibraryRepair.repair(library(broken)))

        // The catalogue's link is backfilled first, so the preferred repair —
        // keeping the user's route — is the one that gets applied.
        #expect(tile.universalLinkString == "https://maps.apple.com/?t=m")
        #expect(tile.strategy == .universalLink)
        #expect(tile.canLaunch)
    }

    @Test("Backfilled, it repairs the route rather than the strategy")
    func prefersKeepingTheRoute() throws {
        let tile = try onlyTile(LibraryRepair.repair(library(FolderTile(
            title: "地图",
            urlString: "maps://",
            catalogID: "maps",
            strategy: .universalLink
        ))))
        // A repair that switched to 中转 would also "work", and would quietly
        // undo a choice the user made. Adding the missing link is the smaller
        // change and the one that honours the setting.
        #expect(tile.strategy == .universalLink)
    }

    @Test("A tile with no catalog entry drops to bounce")
    func repairsWithoutTheCatalog() throws {
        let tile = try onlyTile(LibraryRepair.repair(library(FolderTile(
            title: "手填",
            urlString: "weixin://",
            strategy: .universalLink
        ))))
        #expect(tile.strategy == .bounce)
        #expect(tile.canLaunch)
    }

    @Test("A shortcut tile in a folder gird cannot launch and is moved to bounce")
    func repairsShortcutTiles() throws {
        // 系统快捷启动 needs a SystemShortcut, which only the QuickLaunch widget
        // can carry. In a folder grid it is inert, so keeping it is a blank tile.
        let tile = try onlyTile(LibraryRepair.repair(library(FolderTile(
            title: "快捷指令",
            urlString: "shortcuts://",
            catalogID: "shortcuts",
            strategy: .systemShortcut
        ))))
        #expect(tile.strategy == .bounce)
        #expect(tile.canLaunch)
    }

    @Test("A tile that is already fine is left exactly alone")
    func leavesWorkingTilesAlone() throws {
        let working = FolderTile(
            title: "微信",
            urlString: "weixin://",
            catalogID: "wechat",
            strategy: .bounce
        )
        let repaired = try onlyTile(LibraryRepair.repair(library(working)))
        #expect(repaired == working)
    }

    @Test("Repairing twice changes nothing the second time")
    func isIdempotent() throws {
        let once = LibraryRepair.repair(library(FolderTile(
            title: "地图",
            urlString: "maps://",
            catalogID: "maps",
            strategy: .universalLink
        )))
        #expect(LibraryRepair.repair(once).folders == once.folders)
    }

    @Test("A hand-added tile is matched by name and scheme")
    func repairsTilesWithNoCatalogID() throws {
        // The library that produced this file had exactly this tile: 地图 added
        // by hand, so `catalogID` is nil and only the name and URL identify it.
        let tile = try onlyTile(LibraryRepair.repair(library(FolderTile(
            title: "地图",
            urlString: "maps://",
            strategy: .universalLink
        ))))
        #expect(tile.universalLinkString == "https://maps.apple.com/?t=m")
        #expect(tile.canLaunch)
    }

    @Test("A name that matches nothing is not invented into a link")
    func refusesToGuess() throws {
        let tile = try onlyTile(LibraryRepair.repair(library(FolderTile(
            title: "地图",
            urlString: "iosamap://",   // 高德, not Apple Maps
            strategy: .universalLink
        ))))
        // Same title, different app. The name is not the identity; the scheme is
        // what gets opened, so a link attached on a name match alone would send
        // the user to the wrong app.
        #expect(tile.universalLinkString == nil)
        #expect(tile.strategy == .bounce)
    }

    @Test("A stored link is never overwritten by the catalogue's")
    func doesNotOverwriteAStoredLink() throws {
        let custom = FolderTile(
            title: "地图",
            urlString: "maps://",
            catalogID: "maps",
            strategy: .universalLink,
            universalLinkString: "https://maps.apple.com/?q=coffee"
        )
        let tile = try onlyTile(LibraryRepair.repair(library(custom)))
        // The tile is the authority on itself. A repair pass that overwrites user
        // data because it thinks it knows better is a worse bug than the one it
        // is fixing.
        #expect(tile.universalLinkString == "https://maps.apple.com/?q=coffee")
    }

    /// The repair that would have saved 票牛, and the one that is easiest to
    /// overreach with.
    ///
    /// A tile the catalogue made carries `catalogID`, so the app can tell that
    /// the scheme on disk is its own earlier, wrong answer — `pner://` was a
    /// guess derived from the bundle id, and the app registers it nowhere. The
    /// catalogue is not consulted again after a tile is made, so without this a
    /// corrected catalogue entry helps only tiles that do not exist yet.
    ///
    /// Measured on the device: `pner://` cannot be opened, `piaoniu://` can.
    @Test("A catalogue tile whose stored scheme the catalogue has corrected is fixed")
    func replacesACorrectedScheme() throws {
        let stale = FolderTile(
            title: "票牛",
            urlString: "pner://",
            appStoreID: 1052455390,
            catalogID: "piaoniu"
        )
        let tile = try onlyTile(LibraryRepair.repair(library(stale)))

        #expect(tile.urlString == "piaoniu://home")
        #expect(tile.canLaunch)
    }

    /// The other half of that repair, and the reason it identifies by id rather
    /// than by name.
    ///
    /// The same title with no `catalogID` is a tile the user made. Rewriting its
    /// scheme would be the app overriding a URL the user typed, on the strength
    /// of a name — and the library this was written against really does contain
    /// hand-added 票牛 tiles whose scheme is wrong. They keep it. An
    /// identifiability limit is a smaller harm than a repair that edits user
    /// data it only suspects.
    @Test("A user-made tile with the same name keeps the scheme they chose")
    func doesNotRewriteUnidentifiableTiles() throws {
        let handmade = FolderTile(
            title: "票牛",
            urlString: "pner://",
            appStoreID: 1052455390
        )
        #expect(handmade.catalogID == nil)

        let tile = try onlyTile(LibraryRepair.repair(library(handmade)))

        #expect(tile.urlString == "pner://")
    }

    @Test("A catalogue tile already carrying the right scheme is left alone")
    func leavesACorrectSchemeAlone() throws {
        let current = FolderTile(
            title: "票牛",
            urlString: "piaoniu://home",
            appStoreID: 1052455390,
            catalogID: "piaoniu"
        )
        let tile = try onlyTile(LibraryRepair.repair(library(current)))
        #expect(tile.urlString == "piaoniu://home")
    }
}
