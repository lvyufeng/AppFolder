import Foundation
import Testing
@testable import AppFolderKit

@Suite("Website URL validation")
struct WebsiteURLTests {
    @Test("User input gains HTTPS without altering path, query or fragment semantics", arguments: [
        ("example.com", "https://example.com"),
        ("  example.com/Path?Case=Aa&Case=Bb#Section  ", "https://example.com/Path?Case=Aa&Case=Bb#Section"),
        ("http://example.com/Path", "http://example.com/Path"),
        ("HTTPS://EXAMPLE.COM/Case?Q=Ab%2F#Frag", "HTTPS://EXAMPLE.COM/Case?Q=Ab%2F#Frag"),
        ("example.com:8080/Path", "https://example.com:8080/Path"),
        ("localhost:8080/path", "https://localhost:8080/path"),
        ("127.0.0.1:8080/a", "https://127.0.0.1:8080/a"),
        ("[::1]:8080/a", "https://[::1]:8080/a"),
        ("//example.com/a", "https://example.com/a"),
        ("bücher.de/Path", "https://xn--bcher-kva.de/Path"),
        ("例子.测试/路径?x=中文", "https://xn--fsqu00a.xn--0zwm56d/%E8%B7%AF%E5%BE%84?x=%E4%B8%AD%E6%96%87"),
        ("example.com/hello world?q=a b", "https://example.com/hello%20world?q=a%20b"),
        ("example.com/a%2Fb?next=https%3a%2f%2fother.test%2fAb#C", "https://example.com/a%2Fb?next=https%3a%2f%2fother.test%2fAb#C"),
    ])
    func normalize(pair: (String, String)) {
        let normalized = WebsiteURL.normalized(pair.0)
        #expect(normalized == pair.1)
        #expect(normalized.flatMap(WebsiteURL.validated)?.absoluteString == pair.1)
        #expect(WebsiteURL.normalized(pair.1) == pair.1)
    }

    @Test("Stored URLs accept valid international, local and IP destinations", arguments: [
        "https://example.com", "http://example.com:80/a", "https://example.com:65535/",
        "https://sub.example.com./a", "https://localhost:8080/", "http://router/settings",
        "https://127.0.0.1/", "http://192.168.1.1:8080/", "https://255.255.255.255/",
        "https://[::1]/", "https://[2001:db8::1234]:443/a", "http://[::ffff:192.0.2.1]/",
        "http://[fe80::1%25en0]:8080/", "https://bücher.de/Case", "https://例子.测试/路径",
        "https://xn--bcher-kva.de/a", "https://example.com/a%2Fb?x=%FF&y=Hello+World#Frag",
        "https://example.com/?redirect=javascript:alert(1)",
    ])
    func validStored(value: String) {
        let url = WebsiteURL.validated(value)
        #expect(url != nil)
        #expect(url.flatMap { WebsiteURL.validated($0.absoluteString) } == url)
    }

    @Test("Unsafe or malformed input never becomes a different runnable website", arguments: [
        "", " ", "javascript:alert(1)", "javascript:123", "mailto:a@example.com", "tel:123456",
        "data:text/html,hello", "file:///tmp/test", "ftp://example.com", "appfolder://open",
        "https:example.com", "http:/example.com", "https:///example.com", "https://", "//",
        "https://?q=test", "https://#fragment", "https://user@example.com", "https://user:pass@example.com",
        "https://@example.com", "https://:secret@example.com", "https://a@b@c",
        "https://example.com:", "https://example.com:0", "https://example.com:65536",
        "https://example.com:-1", "https://example.com:+80", "https://example.com:abc",
        "https://example.com:999999999999999999999999999999999999999999",
        "https://example.com:80:90", "https://[::1]:", "https://[::1]:65536",
        "https://[:::1]/", "https://[invalid]/", "https://[::1]trailer/", "https://::1/",
        "https://[fe80::1%25]/", "https://[fe80::1%25en%2F0]/",
        "https://999.2.3.4/", "https://127.1/", "https://2130706433/", "https://010.0.0.1/",
        "https://0x7f.0.0.1/", "https://0X7F000001/", "https://127.0.0.0x1/",
        "https://foo..com/", "https://-foo.com/", "https://foo-.com/", "https://foo_bar.com/",
        "https://%65xample.com/", "https://example.com%2Fevil.test/", "https://example.com\\@evil.test/",
        "https://example.com/%", "https://example.com/%A", "https://example.com/%ZZ",
        "https://example.com/%00", "https://example.com/%09", "https://example.com/%0a",
        "https://example.com/%0D", "https://example.com/%7F", "https://example.com/%E2%80%8E",
        "https://example.com/\npath", "https://example.com\t.evil.test", "https://example.com\r",
        "https://example.com/\u{0000}", "https://example.com/\u{202E}",
        "https://" + String(repeating: "a", count: 64) + ".com/",
    ])
    func rejectBoth(value: String) {
        #expect(WebsiteURL.normalized(value) == nil)
        #expect(WebsiteURL.validated(value) == nil)
    }

    @Test("Stored URL validation never silently repairs user input", arguments: [
        "example.com", "example.com:8080/", "//example.com", " https://example.com", "https://example.com ",
        "https://example.com/a b", "https://example.com/{value}", "https://example.com/\"value\"",
    ])
    func storedRequiresAbsoluteEscapedURL(value: String) {
        #expect(WebsiteURL.validated(value) == nil)
        #expect(WebsiteURL.normalized(value) != nil)
    }

    @Test("Both stored bytes and encoded bytes stay within the shared URL limit")
    func byteLimits() {
        let prefix = "https://example.com/"
        let exact = prefix + String(repeating: "a", count: WebsiteURL.maximumUTF8Bytes - prefix.utf8.count)
        #expect(exact.utf8.count == 2_048)
        #expect(WebsiteURL.validated(exact)?.absoluteString == exact)
        #expect(WebsiteURL.normalized(exact) == exact)
        #expect(WebsiteURL.validated(exact + "a") == nil)
        #expect(WebsiteURL.normalized(exact + "a") == nil)
        let expands = prefix + String(repeating: "中", count: 300)
        #expect(expands.utf8.count < WebsiteURL.maximumUTF8Bytes)
        #expect(WebsiteURL.validated(expands) == nil)
        #expect(WebsiteURL.normalized(expands) == nil)
        let tooLongHost = "https://" + Array(repeating: String(repeating: "a", count: 63), count: 4).joined(separator: ".")
        #expect(WebsiteURL.validated(tooLongHost) == nil)
    }

    @Test("Escaped URL delimiters and case are not decoded, reordered or lowercased")
    func preservesIdentity() throws {
        let value = "https://Example.com/Aa%2fBb?B=Upper&A=Lower&A=Mixed%26Value#Frag%3F"
        let url = try #require(WebsiteURL.validated(value))
        #expect(url.absoluteString == value)
        #expect(WebsiteURL.normalized(value) == value)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/Aa%2fBb")
        #expect(components.percentEncodedQuery == "B=Upper&A=Lower&A=Mixed%26Value")
        #expect(components.percentEncodedFragment == "Frag%3F")
    }
}

@Suite("Website launch intent validation")
struct OpenWebsiteIntentTests {
    @Test("The executable intent rejects invalid stored URLs before returning a system action", arguments: [
        "example.com", "javascript:alert(1)", "https://user:secret@example.com", "https://example.com:65536",
        "https://example.com/%ZZ", "https://example.com\n",
    ])
    func rejectsInvalidLaunch(value: String) async {
        let intent = OpenWebsiteIntent(url: value)
        await #expect(throws: OpenWebsiteError.invalidURL) { try await intent.perform() }
    }
}
