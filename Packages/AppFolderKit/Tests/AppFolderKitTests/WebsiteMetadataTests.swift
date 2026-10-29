import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Website metadata", .serialized)
struct WebsiteMetadataTests {
    private let root = URL(string: "https://example.test/articles/page?keep=1#part")!

    @Test("Head parser handles real attributes and entities without reading scripts or body")
    func headParsing() throws {
        let html = """
        <!doctype html><HTML><HEAD>
        <!-- <title>comment</title><link rel=icon href=https://wrong.test/comment.png> -->
        <script>var x = '<title>script</title><link rel="icon" href="https://wrong.test/script.png">';</script>
        <style>.test:after {content:'<link rel=icon href=/wrong.png>'}</style>
        <base href="/assets/">
        <title>  中文 &amp; Café\n — &#x1F30D;  </title>
        <LINK href='tiny.png?x=1&amp;y=2' rel='shortcut ICON' sizes='16x16'>
        <link sizes="180x180" href="touch.png" rel="apple-touch-icon">
        <link rel="icon" type="image/svg+xml" href="ignore.svg">
        </HEAD><body><link rel="icon" href="https://wrong.test/body.png"></body></HTML>
        """
        let result = WebsiteMetadataHTML.parse(html, baseURL: root)
        #expect(result.title == "中文 & Café — 🌍")
        #expect(result.icons.map(\.absoluteString) == [
            "https://example.test/assets/touch.png", "https://example.test/assets/tiny.png?x=1&y=2"
        ])
    }

    @Test("Invalid titles and icon addresses cannot become saved names or requests")
    func malformedMetadata() {
        let html = """
        <head><title>hidden&#x202E;name</title><meta property="og:title" content="Good &quot;Name&quot;">
        <link rel="icon" href="javascript:alert(1)"><link rel="icon" href="https://user:pass@example.test/icon">
        <link rel="icon" href="data:image/png,AAAA"><link rel="icon" href="/valid.png">
        <link rel="icon" href="/valid.png"></head>
        """
        let result = WebsiteMetadataHTML.parse(html, baseURL: root)
        #expect(result.title == "Good \"Name\"")
        #expect(result.icons == [URL(string: "https://example.test/valid.png")!])
        #expect(WebsiteMetadataHTML.normalizedTitle("\u{0000}bad") == nil)
        #expect(WebsiteMetadataHTML.normalizedTitle(String(repeating: "中", count: 120))?.count == 80)
        #expect(WebsiteMetadataHTML.normalizedTitle(String(repeating: "👨‍👩‍👧‍👦", count: 80)) == nil)
    }

    @Test("Document charset and a cut UTF-8 tail preserve the title")
    func encodings() throws {
        let latin = try #require("<meta charset='windows-1252'><title>Café</title>".data(using: .windowsCP1252))
        #expect(WebsiteMetadataHTML.parse(try #require(WebsiteMetadataHTML.decode(latin, encodingName: nil)), baseURL: root).title == "Café")
        var utf8 = Data("<title>中文网页</title><body>".utf8)
        utf8.append(contentsOf: [0xE4, 0xB8])
        #expect(WebsiteMetadataHTML.parse(try #require(WebsiteMetadataHTML.decode(utf8, encodingName: "utf-8")), baseURL: root).title == "中文网页")
    }

    @Test("Standard named references preserve accented website titles")
    func accentedEntities() {
        let html = "<title>Caf&eacute; &amp; Th&eacute; — M&uuml;nchen, Espa&ntilde;a</title>"
        #expect(WebsiteMetadataHTML.parse(html, baseURL: root).title == "Café & Thé — München, España")
        let social = "<meta property='og:title' content='Cr&egrave;me br&ucirc;l&eacute;e &AMP; pi&ntilde;a'>"
        #expect(WebsiteMetadataHTML.parse(social, baseURL: root).title == "Crème brûlée & piña")
    }

    @Test("The longest standard names and two-scalar references decode without shortening")
    func longAndCompositeEntities() throws {
        let html = "<title>&CounterClockwiseContourIntegral; &NotEqualTilde; &nparsl; &notin;</title>"
        let title = try #require(WebsiteMetadataHTML.parse(html, baseURL: root).title)
        #expect(Array(title.unicodeScalars.map(\.value)) == [0x2233, 0x20, 0x2242, 0x338, 0x20, 0x2AFD, 0x20E5, 0x20, 0x2209])
        let accented = try #require(WebsiteMetadataHTML.parse("<title>&eacute;\u{0304}</title>", baseURL: root).title)
        #expect(Array(accented.unicodeScalars.map(\.value)) == [0xE9, 0x304])
    }

    @Test("Unknown references stay visible and encoded markup is decoded only once")
    func unknownAndSinglePassEntities() {
        let html = "<title>&madeUpEntity; &amp;eacute; &lt;script&gt; &bogus;</title>"
        #expect(WebsiteMetadataHTML.parse(html, baseURL: root).title == "&madeUpEntity; &eacute; <script> &bogus;")
        #expect(WebsiteMetadataHTML.parse("<title>&copy &eacute &notin;</title>", baseURL: root).title == "© é ∉")
    }

    @Test("Legacy references do not rewrite ambiguous URL attribute query parameters")
    func attributeEntityBoundaries() {
        let html = "<title>Icons</title><link rel='icon' href='/caf&eacute;.png?copy=0&copy=1&notit=2&amp;x=3'>"
        #expect(WebsiteMetadataHTML.parse(html, baseURL: root).icons.map(\.absoluteString) == [
            "https://example.test/caf%C3%A9.png?copy=0&copy=1&notit=2&x=3"
        ])
        #expect(WebsiteMetadataHTML.parse("<meta property='og:title' content='A &copy=1 &eacute; B'>", baseURL: root).title == "A &copy=1 é B")
    }

    @Test("PNG and JPEG become bounded square icons without source properties")
    func images() throws {
        for format in ["public.png", "public.jpeg"] {
            let data = try makeImage(width: 512, height: 128, format: format, red: 1)
            let icon = try #require(try WebsiteMetadataArtwork.decode(data))
            #expect(icon.kind == .photo)
            let saved = try #require(icon.pngData)
            let source = try #require(CGImageSourceCreateWithData(saved as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            #expect(properties[kCGImagePropertyPixelWidth] as? Int == 256)
            #expect(properties[kCGImagePropertyPixelHeight] as? Int == 256)
            // ImageIO may synthesize dimensions/color-space EXIF for the new
            // pixels. The source's user comment must not survive the redraw.
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exif?[kCGImagePropertyExifUserComment] == nil)
            #expect(properties[kCGImagePropertyGPSDictionary] == nil)
            let decoded = try #require(icon.decodedPhoto())
            #expect(try rgba(decoded, x: 128, y: 128)[0] > 240)
            #expect(try rgba(decoded, x: 0, y: 0)[3] == 0)
        }
    }

    @Test("ICO chooses a larger directory image rather than its first tiny entry")
    func icoSizes() throws {
        let small = try makeImage(width: 16, height: 16, red: 0)
        let large = try makeImage(width: 256, height: 256, red: 1)
        let data = makeICO([(16, small), (256, large)])
        let icon = try #require(try WebsiteMetadataArtwork.decode(data))
        let image = try #require(icon.decodedPhoto())
        #expect(image.width == 256)
        #expect(try rgba(image, x: 128, y: 128)[0] > 240)
        #expect(try WebsiteMetadataArtwork.decode(data.dropLast()) == nil)
        #expect(try WebsiteMetadataArtwork.decode(Data("<svg/>".utf8)) == nil)
        #expect(try WebsiteMetadataArtwork.decode(Data(repeating: 0, count: WebsiteMetadataArtwork.maximumBytes + 1)) == nil)
        #expect(try WebsiteMetadataArtwork.decode(makeImage(width: 4_097, height: 1, red: 1)) == nil)
    }

    @Test("Redirects are validated and relative icons use final document location")
    func redirectsAndFinalSource() async throws {
        let image = try makeImage(width: 64, height: 64, red: 1)
        MetadataURLProtocol.install { request in
            switch request.url!.path {
            case "/articles/page": return .response(302, ["Location": "/new/page"], [])
            case "/new/page": return .html("<title>Result</title><link rel=icon href='icon.png'>")
            case "/new/icon.png": return .response(200, ["Content-Type": "image/png"], [image])
            default: return .response(404, [:], [])
            }
        }
        let value = try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration())
        #expect(value.title == "Result")
        #expect(value.icon != nil)
        #expect(value.finalURL.absoluteString == "https://example.test/new/page")
        #expect(value.iconSourceURL?.absoluteString == "https://example.test/new/icon.png")
        #expect(root.absoluteString == "https://example.test/articles/page?keep=1#part")
        #expect(MetadataURLProtocol.requests.count == 3)
        #expect(MetadataURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test("Unsafe and looping redirects fail before an unsafe request")
    func redirectLimits() async throws {
        MetadataURLProtocol.install { _ in .response(302, ["Location": "file:///tmp/private"], []) }
        await #expect(throws: WebsiteMetadataError.invalidURL) {
            try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration())
        }
        #expect(MetadataURLProtocol.requests.count == 1)
        MetadataURLProtocol.install { request in .response(302, ["Location": request.url!.absoluteString], []) }
        var limits = WebsiteMetadataLimits()
        limits.maximumRedirects = 2
        await #expect(throws: WebsiteMetadataError.tooManyRedirects) {
            try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration(), limits: limits)
        }
        #expect(MetadataURLProtocol.requests.count == 3)
    }

    @Test("A broken declared icon falls back to the site's own favicon")
    func iconFailureAndFallback() async throws {
        let image = makeICO([(32, try makeImage(width: 32, height: 32, red: 1))])
        MetadataURLProtocol.install { request in
            switch request.url!.path {
            case "/articles/page": return .html("<title>Useful</title><link rel=icon href='/broken.png'>")
            case "/broken.png": return .response(200, ["Content-Type": "image/png"], [Data("invalid".utf8)])
            case "/favicon.ico": return .response(200, ["Content-Type": "image/x-icon"], [image])
            default: return .response(404, [:], [])
            }
        }
        let result = try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration())
        #expect(result.title == "Useful")
        #expect(result.icon != nil)
        #expect(result.iconSourceURL?.absoluteString == "https://example.test/favicon.ico")
        #expect(MetadataURLProtocol.requests.allSatisfy { $0.url!.host() == "example.test" })
    }

    @Test("The HTML prefix is bounded without rejecting a useful head on a large page")
    func htmlBodyLimit() async throws {
        let head = Data("<title>Large page</title></head>".utf8)
        MetadataURLProtocol.install { request in
            if request.url!.path == "/articles/page" {
                return .response(200, ["Content-Type": "text/html", "Content-Length": "1000000"], [head, Data(repeating: 65, count: 500)])
            }
            return .response(404, [:], [])
        }
        var limits = WebsiteMetadataLimits()
        limits.htmlBytes = 100
        let result = try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration(), limits: limits)
        #expect(result.title == "Large page")
        #expect(result.icon == nil)
        MetadataURLProtocol.install { _ in .response(200, ["Content-Type": "text/html"], [Data(repeating: 65, count: 500)]) }
        await #expect(throws: WebsiteMetadataError.responseTooLarge) {
            try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration(), limits: limits)
        }
    }

    @Test("Both advertised and chunked oversized icons preserve the title")
    func iconBodyLimits() async throws {
        for advertised in [true, false] {
            MetadataURLProtocol.install { request in
                if request.url!.path == "/articles/page" { return .html("<title>Keep me</title><link rel=icon href=/too-large>") }
                var headers = ["Content-Type": "image/png"]
                if advertised { headers["Content-Length"] = "10000000" }
                return .response(200, headers, [Data(repeating: 1, count: 1_000)])
            }
            var limits = WebsiteMetadataLimits()
            limits.imageBytes = 100
            let result = try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration(), limits: limits)
            #expect(result.title == "Keep me")
            #expect(result.icon == nil)
            #expect(MetadataURLProtocol.requests.count == 3)
        }
    }

    @Test("Cancellation stops a pending network request and never returns a candidate")
    func cancellation() async throws {
        MetadataURLProtocol.install { _ in .stall }
        let task = Task { try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration()) }
        for _ in 0..<100 where MetadataURLProtocol.requests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(MetadataURLProtocol.requests.count == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        for _ in 0..<100 where MetadataURLProtocol.stopped == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(MetadataURLProtocol.stopped == 1)
    }

    @Test("The total deadline bounds a stalled request independently of URLSession")
    func timeout() async throws {
        MetadataURLProtocol.install { _ in .stall }
        var limits = WebsiteMetadataLimits()
        limits.totalSeconds = 0.05
        await #expect(throws: WebsiteMetadataError.timedOut) {
            try await WebsiteMetadataFetcher.fetch(root, configuration: testConfiguration(), limits: limits)
        }
    }

    @Test("The production configuration has no cookie, credential or cache stores")
    func privacyConfiguration() {
        let value = WebsiteMetadataFetcher.configuration()
        #expect(value.httpCookieStorage == nil)
        #expect(value.urlCredentialStorage == nil)
        #expect(value.urlCache == nil)
        #expect(value.httpShouldSetCookies == false)
        #expect(value.httpCookieAcceptPolicy == .never)
    }

    private func testConfiguration() -> URLSessionConfiguration {
        let config = WebsiteMetadataFetcher.configuration()
        config.protocolClasses = [MetadataURLProtocol.self]
        return config
    }

    private func makeImage(width: Int, height: Int, format: String = "public.png", red: CGFloat) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, format as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "not retained"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeICO(_ images: [(Int, Data)]) -> Data {
        var data = Data([0, 0, 1, 0, UInt8(images.count), 0])
        var offset = 6 + images.count * 16
        func word(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 255) } }
        for (side, image) in images {
            data.append(contentsOf: [side == 256 ? 0 : UInt8(side), side == 256 ? 0 : UInt8(side), 0, 0, 1, 0, 32, 0])
            data.append(contentsOf: word(image.count) + word(offset))
            offset += image.count
        }
        for (_, image) in images { data.append(image) }
        return data
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let start = (y * image.width + x) * 4
        return Array(pixels[start..<(start + 4)])
    }
}

private final class MetadataURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case response(Int, [String: String], [Data])
        case stall
        static func html(_ text: String) -> Reply { .response(200, ["Content-Type": "text/html; charset=utf-8"], [Data(text.utf8)]) }
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var stopCount = 0
    nonisolated(unsafe) private static var generation = 0
    private var requestGeneration = 0
    static var requests: [URLRequest] { lock.withLock { recorded } }
    static var stopped: Int { lock.withLock { stopCount } }
    static func install(_ value: @escaping @Sendable (URLRequest) -> Reply) {
        lock.withLock { handler = value; recorded = []; stopCount = 0; generation += 1 }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let action = Self.lock.withLock {
            requestGeneration = Self.generation
            Self.recorded.append(request)
            return Self.handler
        }
        guard let reply = action?(request) else { return }
        switch reply {
        case .stall: return
        case .response(let status, let headers, let chunks):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        Self.lock.withLock { if requestGeneration == Self.generation { Self.stopCount += 1 } }
    }
}
