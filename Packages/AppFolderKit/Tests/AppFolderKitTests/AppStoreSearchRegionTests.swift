import Foundation
import Testing
@testable import AppFolderKit

@Suite("App Store search regions")
struct AppStoreSearchRegionTests {
    @Test("The storefront catalog excludes geographic regions without an App Store")
    func storefrontMembership() {
        let codes = AppStoreCountry.supportedCodes
        #expect(codes.count == 175)
        #expect(Set(codes).count == codes.count)
        #expect(codes == codes.sorted())
        #expect(codes.allSatisfy { $0.utf8.count == 2 && $0.utf8.allSatisfy { (97...122).contains($0) } })
        for code in ["us", "cn", "gb", "jp", "hk", "tw", "mo", "ne", "ng", "bo", "xk"] {
            #expect(codes.contains(code))
        }
        // These are geographic regions or aliases, not supported picker values.
        for code in ["aq", "bv", "ir", "kp", "uk", "zz", "001", "usa", "xks"] {
            #expect(!AppStoreCountry.isSupported(code))
        }
        #expect(AppStoreCountry.displayName(for: "ne", locale: Locale(identifier: "en")) == "Niger")
        #expect(AppStoreCountry.displayName(for: "ng", locale: Locale(identifier: "en")) == "Nigeria")
    }

    @Test("User input normalizes only known two-letter country codes")
    func userInput() {
        for input in ["jp", "JP", " Jp\n", "\u{3000}jp\u{00a0}"] {
            #expect(AppStoreCountry.normalized(input) == "jp")
        }
        for input in ["", "automatic", "United States", "US/CN", "us?term=x", "us\0", "u s", "ＵＳ", "uſ"] {
            #expect(AppStoreCountry.normalized(input) == nil)
        }
    }

    @Test("Region names are available in each app language and searchable without network access")
    func localizedNames() {
        for language in ["zh-Hans", "en", "zh-Hant", "ja", "ko", "es", "fr", "de", "pt-BR", "ru"] {
            let locale = Locale(identifier: language)
            for code in AppStoreCountry.supportedCodes {
                #expect(!AppStoreCountry.displayName(for: code, locale: locale).isEmpty)
            }
            let japaneseName = AppStoreCountry.displayName(for: "jp", locale: locale)
            #expect(AppStoreCountry.search(query: japaneseName, locale: locale).contains("jp"))
            #expect(AppStoreCountry.search(query: "Japan", locale: locale).contains("jp"))
            #expect(AppStoreCountry.search(query: "JP", locale: locale).contains("jp"))
        }
        #expect(AppStoreCountry.search(query: "日本", locale: Locale(identifier: "zh-Hans")) == ["jp"])
        #expect(AppStoreCountry.search(query: "Deutschland", locale: Locale(identifier: "de")) == ["de"])
    }

    @Test("Search folds case, diacritics and width, combines terms and preserves localized order")
    func textSearch() {
        let locale = Locale(identifier: "fr")
        let baseline = AppStoreCountry.search(query: "Etats Unis", locale: locale)
        #expect(baseline.contains("us"))
        for query in ["ÉTATS UNIS", "Ｅｔａｔｓ　Ｕｎｉｓ", "unis états"] {
            #expect(AppStoreCountry.search(query: query, locale: locale) == baseline)
        }
        #expect(AppStoreCountry.search(query: "japan jp", locale: locale) == ["jp"])
        #expect(AppStoreCountry.search(query: "japan no-such-region", locale: locale).isEmpty)
        let all = AppStoreCountry.search(query: " \n\t", locale: locale)
        #expect(Set(all) == Set(AppStoreCountry.supportedCodes))
        let matching = AppStoreCountry.search(query: "a", locale: locale)
        #expect(matching == all.filter(Set(matching).contains))
        for pair in zip(all, all.dropFirst()) {
            let left = AppStoreCountry.displayName(for: pair.0, locale: locale)
            let right = AppStoreCountry.displayName(for: pair.1, locale: locale)
            #expect(left.compare(right, options: [.caseInsensitive], locale: locale) != .orderedDescending)
        }
    }

    @Test("Automatic retains the old US then China strategy while an explicit choice never falls back")
    func requestOrder() throws {
        let automatic = AppStoreSearchRegion.automatic
        #expect(automatic.rawValue == "automatic")
        #expect(automatic.countryCode == nil)
        #expect(automatic.queryCountries == ["us", "cn"])
        for code in AppStoreCountry.supportedCodes {
            let selected = try #require(AppStoreSearchRegion(countryCode: code.uppercased()))
            #expect(selected.rawValue == code)
            #expect(selected.countryCode == code)
            #expect(selected.queryCountries == [code])
            #expect(selected != automatic)
        }
    }

    @Test("Preference raw values are strict and safely allow a caller to reset obsolete values")
    func preferenceRoundTrip() throws {
        let choices = [AppStoreSearchRegion.automatic]
            + AppStoreCountry.supportedCodes.compactMap(AppStoreSearchRegion.init(countryCode:))
        #expect(Set(choices).count == 176)
        for choice in choices {
            #expect(try #require(AppStoreSearchRegion(rawValue: choice.rawValue)) == choice)
        }
        for invalid in ["", "US", " jp", "automatic ", "Automatic", "aq", "zz", "USA"] {
            #expect(AppStoreSearchRegion(rawValue: invalid) == nil)
            #expect((AppStoreSearchRegion(rawValue: invalid) ?? .automatic).queryCountries == ["us", "cn"])
        }
    }
}
