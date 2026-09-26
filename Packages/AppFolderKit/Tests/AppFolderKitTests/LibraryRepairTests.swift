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
}
