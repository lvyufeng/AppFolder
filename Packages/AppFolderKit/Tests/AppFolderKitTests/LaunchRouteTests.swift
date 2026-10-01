import Foundation
import Testing

@testable import AppFolderKit

/// What the two launch routes actually resolve to.
///
/// These exist because of a real bug: 地图 was configured as 直接打开 while the
/// tile's only URL was `maps://`, `OpenLinkIntent` refused the scheme, and the
/// widget rendered the tile inert. Nothing failed — the tile drew, the tap did
/// nothing, and there was no error anywhere to look at. The fix separates the
/// tile's two URLs, and these tests pin the property that made the bug possible:
/// a tile's launch URL must be the one its route can actually open.
@Suite("Launch routes")
struct LaunchRouteTests {
    private func tile(
        url: String,
        strategy: LaunchStrategy,
        link: String? = nil
    ) -> FolderTile {
        FolderTile(
            title: "T",
            urlString: url,
            strategy: strategy,
            universalLinkString: link
        )
    }

    @Test("A universal link tile launches the link, not the scheme")
    func universalLinkUsesTheLink() throws {
        let tile = tile(
            url: "maps://",
            strategy: .universalLink,
            link: "https://maps.apple.com/?t=m"
        )
        #expect(tile.launchURL?.absoluteString == "https://maps.apple.com/?t=m")
        #expect(tile.canLaunch)
        #expect(tile.universalLinkRefusal == nil)

        // And the intent — the thing the widget actually builds — accepts it.
        let intent = try OpenLinkIntent(tile: tile)
        #expect(intent.url.absoluteString == "https://maps.apple.com/?t=m")
    }

    @Test("A universal link tile with no link does not fall back to its scheme")
    func universalLinkWithoutLinkRefuses() {
        let tile = tile(url: "maps://", strategy: .universalLink)
        // The whole point: `nil`, not `maps://`. Returning the scheme would give
        // `OpenURLIntent` something it ignores, which renders as a live tile that
        // does nothing.
        #expect(tile.launchURL == nil)
        #expect(!tile.canLaunch)
        #expect(tile.universalLinkRefusal != nil)
        #expect(throws: TileError.self) { try OpenLinkIntent(tile: tile) }
    }

    @Test("A bounce tile launches its scheme, whatever else it carries")
    func bounceUsesTheScheme() {
        let tile = tile(
            url: "maps://",
            strategy: .bounce,
            link: "https://maps.apple.com/?t=m"
        )
        #expect(tile.launchURL?.absoluteString == "maps://")
        #expect(tile.canLaunch)
        // Bounce has no refusal to offer: it is the route that always works.
        #expect(tile.universalLinkRefusal == nil)
    }

    @Test("Switching routes neither invents nor destroys the other URL")
    func switchingRoutesKeepsBothURLs() {
        var tile = tile(url: "maps://", strategy: .bounce, link: "https://maps.apple.com/?t=m")
        tile.strategy = .universalLink
        #expect(tile.launchURL?.absoluteString == "https://maps.apple.com/?t=m")
        tile.strategy = .bounce
        #expect(tile.launchURL?.absoluteString == "maps://")
        // Both survived the round trip, which is what lets the editor offer the
        // route switch as a repair rather than as a destructive edit.
        #expect(tile.universalLinkString == "https://maps.apple.com/?t=m")
        #expect(tile.urlString == "maps://")
    }

    @Test("A shortcut tile cannot launch from a folder grid")
    func shortcutTilesAreInert() {
        let tile = tile(url: "shortcuts://", strategy: .systemShortcut)
        #expect(!tile.canLaunch)
        #expect(tile.launchURL?.absoluteString == "shortcuts://")
    }

    @Test("A catalog entry's link travels onto the tile it makes")
    func catalogLinkReachesTheTile() throws {
        let maps = try #require(AppCatalog.all.first { $0.id == "maps" })
        var tile = FolderTile(app: maps)
        #expect(tile.urlString == "maps://")
        #expect(tile.universalLinkString == "https://maps.apple.com/?t=m")
        #expect(tile.appStoreID == maps.appStoreID)

        tile.strategy = .universalLink
        #expect(tile.canLaunch)
    }

    /// Every link in the catalogue is `https://`, because `OpenLinkIntent`
    /// reaches an app through its universal link and nothing else. A `http://`
    /// or scheme-shaped value here would be a tile that cannot work.
    @Test("Every catalog universal link is https")
    func catalogLinksAreHTTPS() {
        for app in AppCatalog.all {
            guard let link = app.universalLink else { continue }
            #expect(link.hasPrefix("https://"), "\(app.id) has a non-https link: \(link)")
        }
    }

    // MARK: - The folder link

    /// Round-trips: the widget builds a folder link and the app reads it back.
    ///
    /// The two are written together and read apart — one in the widget
    /// extension's process, one in the app's — so nothing but a test can catch
    /// them drifting. A link whose id does not survive the trip opens the app
    /// and then shows nothing, which from the Home Screen is indistinguishable
    /// from the tap not registering.
    @Test("A folder link round-trips its id")
    func folderLinkRoundTrips() throws {
        let id = UUID()
        let url = try #require(LaunchLink.folderURL(for: id))
        #expect(url.scheme == "appfolder")
        #expect(LaunchLink.folderID(from: url) == id)
    }

    /// The two hosts must not be confused for one another.
    ///
    /// Both links are `appfolder://` and both carry a query item, so a reader
    /// that checked only the scheme — or that checked the host before deciding —
    /// would hand a bounce's payload to the folder opener. The failure is not a
    /// crash: a URL is a valid string, so the app would open a folder view onto
    /// an id that is really another app's URL, show nothing, and leave the user
    /// certain the widget is broken.
    @Test("A bounce link is not a folder link, and vice versa")
    func theTwoHostsDoNotBleed() throws {
        let bounce = try #require(LaunchLink.bounceURL(for: URL(string: "weixin://")!))
        #expect(LaunchLink.folderID(from: bounce) == nil)
        #expect(LaunchLink.targetURL(from: bounce)?.absoluteString == "weixin://")

        let folder = try #require(LaunchLink.folderURL(for: UUID()))
        #expect(LaunchLink.targetURL(from: folder) == nil)
    }

    /// A folder link whose id is not a UUID is not a folder link.
    ///
    /// The caller's next step is a lookup, and an id that cannot match anything
    /// is the same answer as no id — `nil`, so the app does not open an empty
    /// folder view for a link it cannot honour.
    @Test("A folder link with a malformed id resolves to nothing")
    func malformedFolderIDFails() throws {
        let url = try #require(URL(string: "appfolder://folder?id=not-a-uuid"))
        #expect(LaunchLink.folderID(from: url) == nil)
    }
}
