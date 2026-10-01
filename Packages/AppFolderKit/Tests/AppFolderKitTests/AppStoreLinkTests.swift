import Foundation
import Testing

@testable import AppFolderKit

/// The share-sheet link parser.
///
/// These cases are the specification. The parser's job is to accept the handful of
/// shapes the App Store actually emits and refuse everything else, and "everything
/// else" is not hypothetical — the same hosts serve songs, podcasts, books and
/// developer pages, all of which end in `id<digits>` exactly like an app does.
@Suite("App Store link")
struct AppStoreLinkTests {
    private func parse(_ string: String) -> AppStoreLink? {
        guard let url = URL(string: string) else { return nil }
        return AppStoreLink.parse(url)
    }

    @Test("The canonical link yields its id and region")
    func canonicalLink() {
        let link = parse("https://apps.apple.com/us/app/wechat/id414478124")
        #expect(link?.trackID == 414478124)
        #expect(link?.region == "us")
    }

    @Test("A Chinese-store link keeps its region")
    func chineseStoreLink() {
        let link = parse("https://apps.apple.com/cn/app/微信/id414478124")
        #expect(link?.trackID == 414478124)
        #expect(link?.region == "cn")
    }

    @Test("A region-less link parses with no region")
    func regionlessLink() {
        // The shape the Home Screen share sheet builds from its own template
        // (`https://apps.apple.com/app/id%@`). Region must come back nil rather
        // than guessed, so a caller can tell "unknown" from "us".
        let link = parse("https://apps.apple.com/app/id414478124")
        #expect(link?.trackID == 414478124)
        #expect(link?.region == nil)
    }

    @Test("The older itunes host is accepted")
    func legacyHost() {
        let link = parse("https://itunes.apple.com/us/app/wechat/id414478124?mt=8")
        #expect(link?.trackID == 414478124)
        #expect(link?.region == "us")
    }

    @Test("The App Store's own scheme is accepted")
    func itmsAppssScheme() {
        // What the system rewrites a store link to when it wants the App Store
        // app to handle it. A parser that only understood https would drop the
        // links most likely to arrive from a share sheet.
        let link = parse("itms-appss://apps.apple.com/app/id414478124")
        #expect(link?.trackID == 414478124)
    }

    @Test("Query parameters are ignored")
    func queryIgnored() {
        for query in ["?mt=8", "?l=zh-Hans", "?itscg=30200&itsct=apps_box", "?i=1&mt=8"] {
            let link = parse("https://apps.apple.com/us/app/wechat/id414478124\(query)")
            #expect(link?.trackID == 414478124, "failed for \(query)")
        }
    }

    @Test(
        "Non-app store content is refused",
        arguments: [
            "https://apps.apple.com/us/album/midnights/id1640627838",
            "https://apps.apple.com/us/podcast/the-daily/id1200361736",
            "https://apps.apple.com/us/book/designing-data-intensive-applications/id1394732746",
            "https://apps.apple.com/us/artist/taylor-swift/159260351",
            "https://apps.apple.com/us/developer/apple/284417353",
        ]
    )
    func nonAppContentRefused(_ string: String) {
        // All of these end in `id<digits>` on an accepted host. Only the missing
        // `/app/` marker tells them apart, so this is the case that matters most.
        #expect(parse(string) == nil, "should have refused \(string)")
    }

    @Test(
        "Foreign hosts and schemes are refused",
        arguments: [
            "https://example.com/app/id414478124",
            "https://apps.apple.com.evil.test/app/id414478124",
            "file:///app/id414478124",
            "ftp://apps.apple.com/app/id414478124",
        ]
    )
    func foreignRefused(_ string: String) {
        #expect(parse(string) == nil, "should have refused \(string)")
    }

    @Test(
        "Ids that are not ids are refused",
        arguments: [
            "https://apps.apple.com/us/app/wechat/id",
            "https://apps.apple.com/us/app/wechat/idabc",
            "https://apps.apple.com/us/app/wechat/id-5",
            "https://apps.apple.com/us/app/wechat/id0",
            "https://apps.apple.com/us/app/wechat/414478124",
        ]
    )
    func badIDRefused(_ string: String) {
        #expect(parse(string) == nil, "should have refused \(string)")
    }

    @Test("A slug containing id does not become the track id")
    func slugContainingIDIsNotTheID() {
        // The trailing segment is the only id Apple promises. Taking the first
        // `id`-prefixed segment instead would read this as track id 42.
        let link = parse("https://apps.apple.com/us/app/id42-the-app/id414478124")
        #expect(link?.trackID == 414478124)
    }

    @Test("A trailing slash and extra path segments still parse")
    func trailingSlash() {
        #expect(parse("https://apps.apple.com/us/app/wechat/id414478124/")?.trackID == 414478124)
    }

    @Test("A region that is not two letters is not a region")
    func oddRegion() {
        // `usa` is not a storefront, so it must not be reported as one. The id
        // still parses — refusing the whole link would be the worse trade.
        let link = parse("https://apps.apple.com/usa/app/wechat/id414478124")
        #expect(link?.trackID == 414478124)
        #expect(link?.region == nil)
    }

    @Test("Text is searched for the first App Store link")
    func parseFromText() {
        let text = "看看这个 https://apps.apple.com/cn/app/id414478124 挺好用的"
        let link = AppStoreLink.parseFirst(in: text)
        #expect(link?.trackID == 414478124)
        #expect(link?.region == "cn")
    }

    @Test("Text with no App Store link yields nothing")
    func parseFromTextWithoutLink() {
        #expect(AppStoreLink.parseFirst(in: "就是一句话，没有链接") == nil)
        #expect(AppStoreLink.parseFirst(in: "https://example.com/hello") == nil)
        #expect(AppStoreLink.parseFirst(in: "") == nil)
    }

    @Test("A non-App link in the text does not shadow an App link after it")
    func firstLinkWins() {
        let text = "https://example.com/x then https://apps.apple.com/app/id414478124"
        #expect(AppStoreLink.parseFirst(in: text)?.trackID == 414478124)
    }

    @Test("The lookup endpoint carries the ids and the optional region")
    func lookupURLShape() {
        let url = AppStoreLookup.lookupURL(ids: [414478124, 393765873], country: "cn")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains { $0.name == "id" && $0.value == "414478124,393765873" })
        #expect(items.contains { $0.name == "country" && $0.value == "cn" })

        let bare = AppStoreLookup.lookupURL(ids: [414478124])
        let bareItems = URLComponents(url: bare!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!bareItems.contains { $0.name == "country" })

        #expect(AppStoreLookup.lookupURL(ids: []) == nil)
        #expect(AppStoreLookup.lookupURL(ids: [0, -1]) == nil)
    }
}