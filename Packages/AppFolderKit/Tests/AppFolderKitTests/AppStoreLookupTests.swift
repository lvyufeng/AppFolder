import Foundation
import Testing

@testable import AppFolderKit

/// Parsing the iTunes Search response, and the catalogue reverse-lookup that
/// turns a discovered app into a verified scheme.
@Suite("App Store lookup")
struct AppStoreLookupTests {
    /// A response in the shape Apple actually returns.
    ///
    /// Trimmed to the fields the parser reads, but the *shape* is real: it was
    /// taken from a live `search?term=抖音&country=cn` call, so a future change on
    /// Apple's side that breaks this test also breaks the feature.
    private static let realResponse = Data("""
    {
      "resultCount": 2,
      "results": [
        {
          "trackId": 1142110895,
          "trackName": "抖音",
          "bundleId": "com.ss.iphone.ugc.Aweme",
          "sellerName": "Beijing Microbroadcast Vision Technology Co.,Ltd.",
          "artworkUrl512": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/4d/b7/x.png/512x512bb.jpg",
          "kind": "software"
        },
        {
          "trackId": 1477031443,
          "trackName": "抖音极速版",
          "bundleId": "com.ss.iphone.ugc.aweme.lite",
          "sellerName": "Beijing Microbroadcast Vision Technology Co.,Ltd.",
          "artworkUrl512": "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/ad/59/y.png/512x512bb.jpg",
          "kind": "software"
        }
      ]
    }
    """.utf8)

    @Test("A real response parses into the fields a tile needs")
    func parsesARealResponse() throws {
        let results = AppStoreLookup.parse(Self.realResponse)

        #expect(results.count == 2)
        let first = try #require(results.first)
        #expect(first.trackID == 1142110895)
        #expect(first.name == "抖音")
        #expect(first.bundleID == "com.ss.iphone.ugc.Aweme")
        #expect(first.sellerName?.contains("Microbroadcast") == true)
        #expect(first.artworkURL?.hasPrefix("https://") == true)
    }

    /// A row without an id or a name cannot become a tile, so it is dropped
    /// rather than shown as a row that produces a nameless app.
    @Test("Rows missing an id or a name are dropped, the rest survive")
    func dropsIncompleteRows() {
        let payload = Data("""
        {
          "results": [
            { "trackName": "没有 id" },
            { "trackId": 42 },
            { "trackId": 7, "trackName": "" },
            { "trackId": 9, "trackName": "好" }
          ]
        }
        """.utf8)

        let results = AppStoreLookup.parse(payload)
        #expect(results.count == 1)
        #expect(results.first?.trackID == 9)
    }

    /// Every unreadable input gives the same answer, because the caller's next
    /// step is identical in each case: say nothing was found and leave the manual
    /// path open. A thrown error would only be flattened back to that at the call
    /// site.
    @Test("Unreadable payloads parse to nothing rather than throwing", arguments: [
        Data(),
        Data("not json".utf8),
        Data("{}".utf8),
        Data("{\"results\": null}".utf8),
        Data("{\"results\": {}}".utf8),
        Data("[]".utf8),
    ])
    func unreadablePayloadsAreEmpty(payload: Data) {
        #expect(AppStoreLookup.parse(payload).isEmpty)
    }

    /// The 100px artwork is the only variant guaranteed to exist, so it is an
    /// acceptable substitute when 512 is absent — but never invented.
    @Test("Artwork falls back to the 100px variant")
    func artworkFallsBack() {
        let payload = Data("""
        { "results": [ { "trackId": 1, "trackName": "A", "artworkUrl100": "https://x/100x100bb.jpg" } ] }
        """.utf8)
        #expect(AppStoreLookup.parse(payload).first?.artworkURL == "https://x/100x100bb.jpg")
    }

    @Test("A row with no artwork keeps a nil url rather than an empty string")
    func missingArtworkIsNil() {
        let payload = Data("""
        { "results": [ { "trackId": 1, "trackName": "A" } ] }
        """.utf8)
        #expect(AppStoreLookup.parse(payload).first?.artworkURL == nil)
    }

    // MARK: - Search URL

    @Test("The search URL carries the term, the region, and the app filter")
    func searchURLCarriesItsParameters() throws {
        let url = try #require(AppStoreLookup.searchURL(term: "Keep", country: "cn"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )

        #expect(components.host == "itunes.apple.com")
        #expect(components.path == "/search")
        #expect(items["term"] == "Keep")
        #expect(items["country"] == "cn")
        // Without this the endpoint returns music and books for a name that
        // happens to match a song.
        #expect(items["entity"] == "software")
    }

    /// A term with characters that need escaping is the common case for this
    /// app's audience — 「微信」, and names containing `&` or spaces.
    @Test("A term needing escaping survives the round trip")
    func searchURLEscapesTheTerm() throws {
        let url = try #require(AppStoreLookup.searchURL(term: "微信 & QQ"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let term = components.queryItems?.first { $0.name == "term" }?.value
        #expect(term == "微信 & QQ")
    }

    /// An empty box is not a search. Returning a URL would fire a request for
    /// every character the user deletes on the way back to empty.
    @Test("A blank term has no URL", arguments: ["", "   ", "\n"])
    func blankTermsHaveNoURL(term: String) {
        #expect(AppStoreLookup.searchURL(term: term) == nil)
    }

    // MARK: - Catalogue reverse-lookup

    /// The property the whole feature rests on: a discovered app that the
    /// catalogue already knows yields a verified scheme, so the user never sees
    /// the scheme-entry screen at all.
    @Test("A known App Store id resolves to its catalogue entry")
    func knownIDResolves() throws {
        let entry = try #require(AppCatalog.entry(appStoreID: 1142110895))
        #expect(entry.id == "douyin")
        #expect(entry.confidence == .verified)
    }

    /// An app the catalogue does not know returns nothing, which is what routes
    /// the user to ``SchemeGuess``. Returning a nearby entry would silently give
    /// them another app's scheme — a tile that looks right and opens the wrong
    /// app, which is worse than one that does not open at all.
    @Test("An unknown App Store id resolves to nothing")
    func unknownIDResolvesToNothing() {
        #expect(AppCatalog.entry(appStoreID: 952694580) == nil)   // Keep
        #expect(AppCatalog.entry(appStoreID: 0) == nil)
        #expect(AppCatalog.entry(appStoreID: -1) == nil)
    }
}