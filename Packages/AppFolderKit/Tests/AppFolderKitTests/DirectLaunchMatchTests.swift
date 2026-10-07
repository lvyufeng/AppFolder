import Foundation
import Testing
@testable import AppFolderKit

/// How a direct-launch slot's display name is matched to an App Store app.
///
/// ## The problem this exists to pin
///
/// The system shows a direct-launch slot the app's **own** name. The store carries
/// the **storefront's** name. They are written by different people and agree less
/// often than not, so a naive comparison finds nothing and the slot draws blank.
///
/// Both shapes below are taken from real slots on a real device, with the store
/// response captured from the live endpoint — not invented, because an invented
/// example would be the one that happens to pass.
@Suite("Direct launch match")
struct DirectLaunchMatchTests {
    /// Builds the JSON the search endpoint returns for a list of rows.
    private func payload(_ rows: [(name: String, bundleID: String, id: Int)]) -> Data {
        let results: [[String: Any]] = rows.map {
            ["trackName": $0.name, "bundleId": $0.bundleID, "trackId": $0.id]
        }
        return try! JSONSerialization.data(withJSONObject: ["resultCount": results.count, "results": results])
    }

    /// Matching runs against a URL, so the stub hands one back whatever it is asked.
    private func stubURL() -> URL { URL(string: "https://example.invalid/search")! }

    /// 阿里邮箱: the slot read `Alimail`, the store calls it 阿里邮箱, and the only
    /// thing the two have in common is the app's own bundle id.
    @Test func findsAnAppWhoseStoreNameSharesNothingWithTheDisplayName() async throws {
        let data = payload([
            ("阿里邮箱", "com.alibaba.alimail.store.catalyst2", 1590302171),
            ("myMail box: email client app", "com.my.mail", 722120997),
            ("rednote", "com.xingin.discover", 741292507),
        ])
        let id = await DirectLaunchIcons.matchForTesting(payload: data, name: "Alimail", url: stubURL())
        #expect(id == 1590302171)
    }

    /// 涨乐: the slot read `AI涨乐`, the store calls it `涨乐 - AI涨乐` — a
    /// *containment*, which a prefix test misses. The first real store row is the
    /// right answer and the ones after it are unrelated finance apps.
    @Test func findsAnAppWhoseStoreNameContainsTheDisplayName() async throws {
        let data = payload([
            ("涨乐 - AI涨乐", "com.zhangle.mobile.iphone.nzl", 6511224711),
            ("同花顺-炒股、股票", "cn.com.10jqka.IHexin", 303191318),
            ("涨乐财富通-炒股票理财就选华泰", "com.zhangle.mobile.iphone.licai", 379594830),
        ])
        let id = await DirectLaunchIcons.matchForTesting(payload: data, name: "AI涨乐", url: stubURL())
        #expect(id == 6511224711)
    }

    /// A short term must not be matched against bundle ids — "AI" appears in
    /// countless identifiers and would attach a stranger's icon to the slot.
    @Test func aShortNameDoesNotMatchByBundleID() async throws {
        let data = payload([
            ("Something Else", "com.example.aibrowser", 111),
        ])
        let id = await DirectLaunchIcons.matchForTesting(payload: data, name: "AI", url: stubURL())
        #expect(id == nil)
    }

    /// Nothing plausible in the results means no icon, not a wrong one.
    @Test func unrelatedResultsResolveToNothing() async throws {
        let data = payload([
            ("同花顺-炒股、股票", "cn.com.10jqka.IHexin", 303191318),
            ("东方财富-股票、炒股、理财", "com.eastmoney.iphone", 423525686),
        ])
        let id = await DirectLaunchIcons.matchForTesting(payload: data, name: "不存在的应用名", url: stubURL())
        #expect(id == nil)
    }

    // MARK: - Apple's own apps

    /// 日历 comes back as Apple's row, not the third party the ordinary matcher
    /// would pick.
    ///
    /// This is the whole reason the system-app lookup exists. Searching `Calendar`
    /// on a Chinese storefront returns *Calendars* by Readdle **first** and
    /// `Google 日历` second, and Apple's own last — so ``bestMatch(payload:name:)``,
    /// which ranks by name containment and takes the shortest, lands on a stranger's
    /// calendar. The rows below are the live response, in its real order.
    @Test func anAppleAppIsPickedByBundleIDNotByName() async throws {
        let data = payload([
            ("Calendars – 日历、待办事项列表和日程表", "com.readdle.calendars.app", 608834326),
            ("Google 日历", "com.google.calendar", 909319292),
            ("日历", "com.apple.mobilecal", 1108185179),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data) == 1108185179)
    }

    /// The English storefront's ordering, which is worse for a name matcher: the
    /// contested words come back back-to-back and Apple's row is not last.
    @Test func theEnglishOrderingAlsoPicksApple() async throws {
        let data = payload([
            ("Calendar", "com.apple.mobilecal", 1108185179),
            ("Google Calendar: Get Organized", "com.google.calendar", 909319292),
            ("Calendars: Schedule Planner", "com.readdle.calendars.app", 608834326),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data) == 1108185179)
    }

    /// A seller called "Apple" is not enough — only the bundle prefix is.
    ///
    /// Nothing outside Apple can ship a `com.apple.*` bundle id, so the prefix is
    /// the test that cannot be satisfied by a lookalike. A name or seller match
    /// could be: the search endpoint returns rows whose *seller* is some unrelated
    /// company and whose *name* is "Calendar".
    @Test func aLookalikeWithoutTheBundlePrefixIsRejected() async throws {
        let data = payload([
            ("Calendar", "com.someone.apple.calendar", 111111),
            ("Apple 日历", "com.example.calendar", 222222),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data) == nil)
    }

    /// A store with no listing for a system app yields nothing rather than a
    /// stranger — the caller then keeps the symbol it already had.
    @Test func noAppleRowMeansNoID() async throws {
        let data = payload([
            ("APN Settings", "com.natureweb.apn", 1072681526),
            ("手机设置助手", "com.expatlife.settings", 6761478056),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data) == nil)
    }

    /// Every entry in the catalogue that carries no App Store id, is one of Apple's
    /// own apps, and has a symbol to fall back to.
    ///
    /// The system-app lookup above takes `isSystemApp` as its trigger and then
    /// leans on two things: that such an entry has a symbol (the grey square it is
    /// replacing) and that a third-party entry without an id would never reach it.
    /// Both are properties of the data, not of the code, so they are checked
    /// against the data.
    ///
    /// This caught a real entry when it was first written — the 自定义链接
    /// placeholder, which has no id, no symbol, and is not a system app. It is
    /// excluded from the lookup by the `isSystemApp` gate; without that gate it
    /// would have spent a request per timeline to be told the store has never
    /// heard of "Custom Link".
    @Test func appStoreIDIsAbsentOnlyForSystemApps() {
        let missing = AppCatalog.all.filter { $0.appStoreID == nil }
        #expect(!missing.isEmpty, "if this ever empties, the system-app lookup is dead code")

        for app in missing where app.isSystemApp {
            #expect(app.symbolName != nil, "\(app.name) has no id and no symbol to fall back to")
        }
    }
}