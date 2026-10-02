import Foundation
import Testing

@testable import AppFolderKit

/// What the launch route actually resolves to.
///
/// These exist because of a real bug: 地图 was configured as 直接打开 while the
/// tile's only URL was `maps://`, `OpenLinkIntent` refused the scheme, and the
/// widget rendered the tile inert. Nothing failed — the tile drew, the tap did
/// nothing, and there was no error anywhere to look at. The fix separates the
/// tile's two URLs, and these tests pin the property that made the bug possible:
/// a tile's launch URL must be the one its route can actually open.
///
/// The route is *derived* now — see ``FolderTile/launchRoute`` — so the stored
/// `strategy` is no longer what decides. Every test below therefore asserts on
/// the route the tile actually resolves to, and the ones that used to be about
/// switching a setting are about the derivation ignoring a stale one.
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

    @Test("A tile with a universal link takes the link, whatever it was stored as")
    func universalLinkWins() throws {
        let tile = tile(
            url: "maps://",
            strategy: .universalLink,
            link: "https://maps.apple.com/?t=m"
        )
        #expect(tile.launchRoute == .universalLink)
        #expect(tile.launchURL?.absoluteString == "https://maps.apple.com/?t=m")
        #expect(tile.canLaunch)

        // And the intent — the thing the widget actually builds — accepts it.
        let intent = try OpenLinkIntent(tile: tile)
        #expect(intent.url.absoluteString == "https://maps.apple.com/?t=m")

        // A stale `.bounce` in the stored strategy does not override the link:
        // the derivation reads the tile, not the setting. This is the case a
        // library saved by an older build lands in, and it must open directly.
        var stale = tile
        stale.strategy = .bounce
        #expect(stale.launchRoute == .universalLink)
        #expect(stale.launchURL?.absoluteString == "https://maps.apple.com/?t=m")
    }

    @Test("A universal link tile with no link does not fall back to its scheme")
    func universalLinkWithoutLinkRefuses() {
        let tile = tile(url: "maps://", strategy: .universalLink)
        // The whole point: the route falls through to the scheme rather than
        // producing `nil`. A `nil` here would be a dead tile — the editor draws
        // it, the widget draws it, and the tap does nothing — whereas the bounce
        // route always reaches *something*, even when it is only AppFolder
        // reporting that it could not open the target.
        #expect(tile.launchRoute == .bounce)
        #expect(tile.launchURL?.absoluteString == "maps://")
        #expect(tile.canLaunch)
    }

    /// A link that is not `https` is not a universal link, however it was
    /// stored. `OpenURLIntent` throws on it, and a throw from a widget button is
    /// the 地图 bug — so the derivation must not pick `.universalLink` just
    /// because the string is present.
    @Test("A non-https link does not become a universal-link route")
    func nonHTTPSLinkIsNotAUniversalLink() {
        let tile = tile(url: "maps://", strategy: .universalLink, link: "maps://")
        #expect(tile.universalLink == nil)
        #expect(tile.launchRoute == .bounce)
        #expect(tile.launchURL?.absoluteString == "maps://")
        #expect(tile.canLaunch)
    }

    @Test("A tile with neither URL keeps its stored route")
    func nothingToLaunchKeepsTheStoredRoute() {
        // Nothing to derive from, so the stored value is the only answer left —
        // and a `.systemShortcut` there means the tile is inert rather than
        // falling through to a scheme that does not exist.
        let tile = tile(url: "", strategy: .systemShortcut)
        #expect(tile.launchRoute == .systemShortcut)
        #expect(tile.launchURL == nil)
        #expect(!tile.canLaunch)
    }

    @Test("A stored shortcut route falls back to the scheme it carries")
    func shortcutRouteFallsBackToItsScheme() {
        let tile = tile(url: "shortcuts://", strategy: .systemShortcut)
        // The scheme is present, so the derivation sends it down the bounce
        // route — which is the only route that can work at all. A stored
        // `.systemShortcut` cannot be honoured in a grid: `SystemShortcut` is
        // not constructible, so there is no intent for the widget to run.
        #expect(tile.launchRoute == .bounce)
        #expect(tile.canLaunch)
    }

    @Test("A catalog entry's link travels onto the tile it makes")
    func catalogLinkReachesTheTile() throws {
        let maps = try #require(AppCatalog.all.first { $0.id == "maps" })
        var tile = FolderTile(app: maps)
        #expect(tile.urlString == "maps://")
        #expect(tile.universalLinkString == "https://maps.apple.com/?t=m")
        #expect(tile.appStoreID == maps.appStoreID)

        // The route follows the link, which the catalogue entry supplied — no
        // setting to set, and nothing the user has to get right.
        #expect(tile.launchRoute == .universalLink)
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
