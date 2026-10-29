import Foundation
import Testing
@testable import AppFolderKit

@Suite("Website browser destinations")
struct WebsiteBrowserTests {
    @Test("App-default resolution is explicit, cannot recurse and never overrides concrete website choices")
    func appDefaultResolution() throws {
        #expect(WebsiteBrowser.concreteCases == [.systemDefault, .inAppSafari, .chrome, .firefox])
        #expect(Set(WebsiteBrowser.allCases) == Set(WebsiteBrowser.concreteCases + [.appDefault]))
        let url = try #require(URL(string: "https://example.org/a%2Fb?q=A%2BB#part"))
        #expect(WebsiteBrowser.appDefault.externalURL(for: url) == nil)
        for appBrowser in WebsiteBrowser.allCases {
            for explicit in WebsiteBrowser.concreteCases {
                #expect(explicit.resolved(using: appBrowser) == explicit)
            }
            let resolved = WebsiteBrowser.appDefault.resolved(using: appBrowser)
            #expect(resolved == (appBrowser == .appDefault ? .systemDefault : appBrowser))
            #expect(resolved != .appDefault)
        }
        #expect(WebsiteBrowser.appDefault.resolved(using: .chrome).externalURL(for: url)?.absoluteString
                == "googlechromes://example.org/a%2Fb?q=A%2BB#part")
    }

    @Test("Chrome replaces only the HTTP(S) scheme, preserving opaque path, query and fragment")
    func chromeTransport() throws {
        for (scheme, browserScheme) in [("http", "googlechrome"), ("https", "googlechromes"), ("HTTPS", "googlechromes")] {
            let suffix = "://example.org:8443/a%2Fb/%25?q=A%2BB&x=1&x=2&next=%2Ffoo%3Fx%3D1%26y%3D2#part%202"
            let url = try #require(URL(string: scheme + suffix))
            #expect(WebsiteBrowser.chrome.externalURL(for: url)?.absoluteString == browserScheme + suffix)
            #expect(WebsiteBrowser.systemDefault.externalURL(for: url) == url)
            #expect(WebsiteBrowser.inAppSafari.externalURL(for: url) == nil)
        }
    }

    @Test("Firefox carries exactly one encoded complete URL without decoding the target's percent escapes")
    func firefoxPayload() throws {
        for raw in [
            "https://example.org/a%2Fb?q=A%2BB&x=1&x=2&empty=&plus=+&percent=%25#part%202",
            "http://[::1]:8080/a?next=https%3A%2F%2Fexample.org%2F%3Fa%3D1%26b%3D2#nested",
            "https://例子.测试/搜索?q=中文#片段",
            "https://example.org/?", "https://example.org/#"
        ] {
            let original = try #require(WebsiteURL.validated(raw))
            let transport = try #require(WebsiteBrowser.firefox.externalURL(for: original))
            let components = try #require(URLComponents(url: transport, resolvingAgainstBaseURL: false))
            #expect(components.scheme == "firefox" && components.host == "open-url")
            #expect(components.fragment == nil && components.path.isEmpty)
            let items = try #require(components.queryItems)
            #expect(items.count == 1 && items[0].name == "url")
            #expect(items[0].value == original.absoluteString)
        }
    }

    @Test("External browser mapping never promotes another scheme or an untrusted relative URL")
    func rejectsInvalidTargets() throws {
        var urls = ["javascript:alert(1)", "file:///private/data", "appfolder://website", "https://user:secret@example.org/",
                    "https://example.org:99999/", "https://example.org/" + String(repeating: "x", count: 2_048)]
            .compactMap(URL.init(string:))
        let base = try #require(URL(string: "https://example.org/"))
        urls.append(try #require(URL(string: "private", relativeTo: base)))
        for browser in WebsiteBrowser.allCases {
            for url in urls { #expect(browser.externalURL(for: url) == nil) }
        }
    }
}
