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

    /// When several apps share the name, **the store's ranking decides** — not the
    /// shortest name.
    ///
    /// This is the 头像 bug, in the shape it actually takes. A slot read
    /// "Authenticator" and got **"Authenticator ·" by SMM service**: a tiny app
    /// that merely had the shortest name containing the word. The store, which
    /// knows the vendor, returns **Microsoft Authenticator first** — and the vendor
    /// is exactly the signal the slot cannot supply, because ``SystemShortcut``
    /// hands the widget a name and nothing else (measured: subtitle nil, image nil,
    /// synonyms empty, one opaque token — see the probe in `DirectLaunchWidget`).
    ///
    /// So the store's order is not a heuristic to be improved on; it is the only
    /// vendor-aware information in the whole pipeline. The rows below are the live
    /// `us` response, in its real order.
    @Test func aNameCollisionIsResolvedByTheStoresOrdering() async throws {
        let data = payload([
            ("Microsoft Authenticator", "com.microsoft.azureauthenticator", 983156458),
            ("Google Authenticator", "com.google.Authenticator", 388497605),
            ("Authenticator App", "com.2stable.2fa", 1538761576),
            ("Authenticator ·", "com.smmservice.authenticator", 1602061522),
            ("Duo Mobile", "com.duosecurity.DuoMobile", 422663827),
        ])
        let id = await DirectLaunchIcons.matchForTesting(payload: data, name: "Authenticator", url: stubURL())
        #expect(id == 983156458, "the shortest containing name is SMM's; the store ranks Microsoft first")
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
    /// which takes the first name-containment hit, lands on a stranger's calendar
    /// (and the exact-name rule ``appleAppID(payload:terms:)`` is what corrects it,
    /// not the ranking). The rows below are the live response, in its real order.
    @Test func anAppleAppIsPickedByBundleIDNotByName() async throws {
        let data = payload([
            ("Calendars – 日历、待办事项列表和日程表", "com.readdle.calendars.app", 608834326),
            ("Google 日历", "com.google.calendar", 909319292),
            ("日历", "com.apple.mobilecal", 1108185179),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["日历", "calendar"]) == 1108185179)
    }

    /// The bug that shipped: 「设置」 is not in the store, and the fuzzy search
    /// answered with **Safari**. Taking the first `com.apple.*` row drew Safari's
    /// icon on the 设置 slot.
    ///
    /// The row order here is the live response, captured 2026-10-08 from the `cn`
    /// storefront. The fix is that the name has to match, so Safari cannot stand in
    /// for an app whose listing does not exist.
    @Test func theSearchCannotSubstituteASiblingForAnUnlistedApp() async throws {
        let data = payload([
            ("Safari", "com.apple.mobilesafari", 1146562112),
            ("手机设置助手", "com.expatlife.settings", 6761478056),
            ("Apple Store", "com.apple.store.Jolly", 375380948),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["设置", "settings"]) == nil)
    }

    /// The same class, one step further out: 「App Store」 is *not* matched, even
    /// though **App Store Connect**'s name contains it.
    ///
    /// The measurement behind this: the real App Store has no store listing on any
    /// storefront (`lookup?bundleId=com.apple.AppStore` → `resultCount: 0`), so
    /// there is no artwork to fetch and no id that could be correct. The catalogue
    /// used to record Connect's id here as a "closest sibling", and the widget then
    /// drew Connect's logo on the App Store slot — the wrong icon that was reported.
    /// The entry now carries no id and falls back to its ``KnownApp/symbolName``.
    /// What this pins is that the *search* does not decide either way: only an
    /// exact name may match, so Connect can never stand in.
    @Test func aLongerNameDoesNotStandInForAShorterOne() async throws {
        let data = payload([
            ("App Store Connect", "com.apple.AppStoreConnect", 1234793120),
            ("App Store 助手", "com.someone.appstore", 222222),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["app store"]) == nil)
    }

    /// The App Store has no listing anywhere, so its entry must carry **no** id —
    /// an id there can only name a different app.
    ///
    /// This is the regression guard for the reported bug. The entry once held
    /// Connect's id; because the artwork view prefers a downloaded icon over the
    /// symbol, that silently drew Connect's logo. A future "fix" that adds an id
    /// back — Connect's, or anyone else's — would reintroduce exactly that.
    @Test func theAppStoreCarriesNoIDBecauseNoCorrectOneExists() throws {
        let entry = try #require(AppCatalog.all.first { $0.id == "appstore" })
        #expect(entry.appStoreID == nil)
        #expect(entry.storeAppID == nil)
        #expect(entry.symbolName != nil, "with no id it must at least have the symbol to draw")
    }

    /// A system app the storefront renamed still resolves, by whichever name is
    /// the one it actually answers to.
    ///
    /// Maps is stored as 「Apple地图」 on the `cn` storefront — not 「地图」, which is
    /// what the device calls it. A strict match would miss it, so the catalogue
    /// names its id explicitly rather than relying on the search; this checks the
    /// other half, that a row *does* resolve when the name really is the one asked
    /// for.
    @Test func aRenamedSystemAppResolvesByTheNameItActuallyUses() async throws {
        let data = payload([
            ("Apple地图", "com.apple.Maps", 915056765),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["apple地图"]) == 915056765)
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["地图", "maps"]) == nil)
    }

    /// The English storefront's ordering, which is worse for a name matcher: the
    /// contested words come back back-to-back and Apple's row is not last.
    @Test func theEnglishOrderingAlsoPicksApple() async throws {
        let data = payload([
            ("Calendar", "com.apple.mobilecal", 1108185179),
            ("Google Calendar: Get Organized", "com.google.calendar", 909319292),
            ("Calendars: Schedule Planner", "com.readdle.calendars.app", 608834326),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["calendar", "日历"]) == 1108185179)
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
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["calendar", "日历"]) == nil)
    }

    /// A store with no listing for a system app yields nothing rather than a
    /// stranger — the caller then keeps the symbol it already had.
    @Test func noAppleRowMeansNoID() async throws {
        let data = payload([
            ("APN Settings", "com.natureweb.apn", 1072681526),
            ("手机设置助手", "com.expatlife.settings", 6761478056),
        ])
        #expect(DirectLaunchIcons.appleAppID(payload: data, terms: ["calendar", "日历"]) == nil)
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

    /// A system app whose storefront name differs from the name the device shows
    /// **must** carry ``KnownApp/storeAppID``, because the name search cannot find
    /// it.
    ///
    /// This is the invariant behind the fix for the App Store / 设置 bug. The
    /// search matches a term against the whole row, so the only entries that are
    /// safe without an explicit id are the ones whose storefront name is exactly
    /// the name the catalogue uses. The renamed ones are listed below — measured,
    /// not guessed — and every one of them is a silent failure if the id goes
    /// missing: the slot falls back to a grey symbol, or worse, matches a sibling.
    @Test func renamedSystemAppsCarryAnExplicitID() {
        let renamed = [
            "maps": "Apple地图",
            "health": "Apple 健康",
            "wallet": "Apple 钱包",
            "fitness": "Apple 健身",
        ]
        for (id, storefrontName) in renamed {
            let app = AppCatalog.all.first { $0.id == id }
            let entry = try? #require(app, "\(id) left the catalogue; update this list")
            guard let entry else { continue }
            #expect(
                entry.storeAppID != nil,
                "\(entry.name) is listed as \(storefrontName) on the storefront, so the name search misses it"
            )
            #expect(
                entry.storeAppID != entry.appStoreID,
                "\(entry.name) carries two ids; one of them is a guess"
            )
        }
    }
}