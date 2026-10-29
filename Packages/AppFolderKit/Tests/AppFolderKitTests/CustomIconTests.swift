import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AppFolderKit

@Suite("Custom widget icons")
struct CustomIconTests {
    @Test("Symbols and colors are constrained to drawable choices")
    func symbolsAndColors() throws {
        let icon = try #require(CustomIcon.symbol("heart.fill", backgroundHex: "aabbcc"))
        #expect(icon.backgroundHex == "#AABBCC")
        #expect(icon.kind == .symbol)
        #expect(icon.pngData == nil)
        #expect(CustomIcon.symbol("not.a.real.symbol") == nil)
        #expect(CustomIcon.symbol("heart.fill", backgroundHex: "#ff") == nil)
        #expect(CustomIcon.symbol("heart.fill", backgroundHex: "#gg0000") == nil)
    }

    @Test("Short text supports initials, Han characters, flags, and joined emoji")
    func emojiValidation() {
        for emoji in ["😀", "🇨🇳", "👨‍👩‍👧‍👦", "❤️", "1️⃣", "👍🏽", "AB", "通勤", "A", "😀😀"] {
            #expect(CustomIcon.emoji(emoji)?.value == emoji)
        }
        #expect(CustomIcon.emoji("  🌻 ")?.value == "🌻")
        for invalid in ["", "abc", "😀😀😀", "\n", "A\n", "\u{200B}", "\u{202E}A", "\u{0301}", "\u{200D}", "\tA"] {
            #expect(CustomIcon.emoji(invalid) == nil)
        }
    }

    @Test("Only bounded, decodable square PNGs are accepted")
    func boundedPhoto() throws {
        let png = try makeImage(width: 32, height: 32)
        let icon = try #require(CustomIcon.photo(pngData: png))
        #expect(icon.kind == .photo)
        #expect(icon.pngData == png)
        #expect(CustomIcon.photo(pngData: try makeImage(width: 257, height: 257)) == nil)
        #expect(CustomIcon.photo(pngData: try makeImage(width: 32, height: 16)) == nil)
        #expect(CustomIcon.photo(pngData: try makeImage(width: 32, height: 32, type: "public.jpeg")) == nil)
        #expect(CustomIcon.photo(pngData: Data("not an image".utf8)) == nil)
        #expect(CustomIcon.photo(pngData: Data(png.prefix(32))) == nil)
        #expect(CustomIcon.photo(pngData: png + Data(repeating: 0, count: CustomIcon.maximumPhotoBytes)) == nil)
    }

    @Test("Truncated or damaged PNG containers are rejected even when their pixels decode")
    func completePNGContainer() throws {
        let original = try makeImage(width: 256, height: 256)
        // ImageIO can report a complete frame after recovering missing PNG bytes.
        #expect(CustomIcon.photo(pngData: Data(original.dropLast())) == nil)
        #expect(CustomIcon.photo(pngData: Data(original.dropLast(12))) == nil)
        #expect(CustomIcon.photo(pngData: Data(original.prefix(original.count / 2))) == nil)
        var badChecksum = original
        badChecksum[badChecksum.count - 1] ^= 1
        #expect(CustomIcon.photo(pngData: badChecksum) == nil)
    }

    @Test("Decoding cannot bypass icon validation")
    func decoderValidation() throws {
        let decoder = JSONDecoder()
        for json in [
            ##"{"kind":"symbol","value":"not.a.symbol","backgroundHex":"#000000"}"##,
            ##"{"kind":"emoji","value":"wrong","backgroundHex":"#000000"}"##,
            ##"{"kind":"photo","value":"","backgroundHex":"#000000","pngData":"bm90IGEgcG5n"}"##,
            ##"{"kind":"unknown","value":"","backgroundHex":"#000000"}"##,
        ] {
            #expect(throws: (any Error).self) { try decoder.decode(CustomIcon.self, from: Data(json.utf8)) }
        }
        let icon = try #require(CustomIcon.emoji("🚀"))
        #expect(try decoder.decode(CustomIcon.self, from: JSONEncoder().encode(icon)) == icon)
    }

    @Test("Names normalize, preserve display spelling, and survive a fresh reader")
    func durableRoundTrip() throws {
        try withRepository { repository, directory in
            let icon = try #require(CustomIcon.symbol("star.fill"))
            #expect(repository.set(icon, name: "  My Shortcut \n"))
            let reopened = CustomIconRepository(directory: directory)
            #expect(reopened.icon(name: "my shortcut") == icon)
            #expect(reopened.icon(name: " MY SHORTCUT ") == icon)
            #expect(reopened.displayNames == ["my shortcut": "My Shortcut"])
            #expect(reopened.all == ["my shortcut": CustomIconVariants(standard: icon)])
            #expect(reopened.revision == repository.revision)
        }
    }

    @Test("Updating and clearing an icon preserves other icons and changes revision")
    func independentEdits() throws {
        try withRepository { repository, _ in
            let a = try #require(CustomIcon.symbol("star.fill"))
            let b = try #require(CustomIcon.emoji("🚀"))
            #expect(repository.set(a, name: "First"))
            #expect(repository.set(b, name: "Second"))
            let before = repository.revision
            #expect(repository.set(a, name: "First"))
            #expect(repository.revision == before)
            #expect(repository.set(b, name: "First"))
            #expect(repository.revision != before)
            #expect(repository.icon(name: "Second") == b)
            #expect(repository.set(nil, name: "First"))
            #expect(repository.set(nil, name: "First"))
            #expect(repository.icon(name: "First") == nil)
            #expect(repository.all == ["second": CustomIconVariants(standard: b)])
        }
    }

    @Test("A saved photo is self-contained and replacement leaves no orphan file")
    func photoRoundTrip() throws {
        try withRepository { repository, directory in
            let png = try makeImage(width: 64, height: 64)
            let photo = try #require(CustomIcon.photo(pngData: png))
            #expect(repository.set(photo, name: "Photo"))
            let reopened = CustomIconRepository(directory: directory)
            #expect(reopened.icon(name: "photo")?.pngData == png)
            #expect(repository.set(CustomIcon.symbol("camera.fill"), name: "Photo"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
            #expect(repository.set(nil, name: "Photo"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    @Test("Names never become file paths and blank names cannot overwrite anything")
    func filenamesAreOpaque() throws {
        try withRepository { repository, directory in
            let icon = try #require(CustomIcon.symbol("folder.fill"))
            #expect(repository.set(icon, name: "../../outside"))
            #expect(repository.icon(name: "../../outside") == icon)
            let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(filenames.count == 1)
            #expect(filenames[0].count == 69)
            #expect(!filenames[0].contains("outside"))
            #expect(!repository.set(icon, name: "  \n"))
            #expect(!repository.set(icon, name: String(repeating: "a", count: 1_025)))
            #expect(repository.all.count == 1)
        }
    }

    @Test("Corrupt records are skipped without discarding unaffected icons")
    func corruptRecordIsolation() throws {
        try withRepository { repository, directory in
            let icon = try #require(CustomIcon.symbol("star.fill"))
            #expect(repository.set(icon, name: "bad"))
            let badURL = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
            #expect(repository.set(icon, name: "good"))
            try Data("broken json".utf8).write(to: badURL)
            #expect(repository.icon(name: "bad") == nil)
            #expect(repository.all == ["good": CustomIconVariants(standard: icon)])
            #expect(repository.displayNames == ["good": "good"])
            #expect(repository.set(icon, name: "bad"))
            #expect(repository.all.count == 2)
        }
    }

    @Test("Missing shared storage and disk errors report failure without private fallback")
    func unavailableStorage() throws {
        let icon = try #require(CustomIcon.symbol("star.fill"))
        let missing = CustomIconRepository(directory: nil)
        #expect(!missing.isAvailable)
        #expect(!missing.set(icon, name: "Example"))
        #expect(!missing.set(nil, name: "Example"))
        #expect(missing.all.isEmpty)
        try withRepository { _, directory in
            try Data("not a directory".utf8).write(to: directory)
            let unwritable = CustomIconRepository(directory: directory)
            #expect(!unwritable.set(icon, name: "Example"))
        }
    }

    private func withRepository(_ body: (CustomIconRepository, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CustomIconTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(CustomIconRepository(directory: directory), directory)
    }

    private func makeImage(width: Int, height: Int, type: String = "public.png") throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
