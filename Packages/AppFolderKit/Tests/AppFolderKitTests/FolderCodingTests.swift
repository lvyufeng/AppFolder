import Foundation
import Testing

@testable import AppFolderKit

/// The on-disk format is the one place where a mistake costs the user their
/// data, so it gets the only tests in the package.
@Suite("Library decoding")
struct FolderCodingTests {
    // MARK: - Dates

    /// The regression that motivated ``FolderCoding``: one ISO-8601 date — the
    /// shape any hand-written or exported file will use — used to fail the
    /// decode of the entire library, which `FolderStore` then quarantined and
    /// replaced with nothing. A folder of nine tiles disappeared because of one
    /// timestamp.
    @Test("Dates written as ISO-8601 strings decode")
    func decodesISO8601Dates() throws {
        let json = """
        {
          "schemaVersion": 1,
          "folders": [
            {
              "id": "\(UUID().uuidString)",
              "name": "常用",
              "colorHex": "",
              "updatedAt": "2026-09-26T16:48:00Z",
              "tiles": []
            }
          ],
          "installedSchemes": [],
          "probedSchemes": []
        }
        """.data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)

        #expect(library.folders.count == 1)
        #expect(library.folders.first?.name == "常用")
    }

    @Test("Dates with fractional seconds decode too")
    func decodesISO8601WithFractionalSeconds() throws {
        let json = #"{"schemaVersion":1,"folders":[],"lastProbeAt":"2026-09-26T16:48:00.123Z"}"#
            .data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)

        #expect(library.lastProbeAt != nil)
    }

    /// What the app itself writes — `JSONEncoder`'s default date representation,
    /// seconds since 2001-01-01. Changing the decoder must not break this.
    @Test("Round-trips the numeric date format the app writes")
    func roundTripsWrittenFormat() throws {
        let original = FolderLibrary(
            folders: [Folder(name: "常用", tiles: [FolderTile(title: "微信", urlString: "weixin://")])],
            installedSchemes: ["weixin"],
            probedSchemes: ["weixin", "mqq"],
            lastProbeAt: Date(timeIntervalSinceReferenceDate: 812_104_549.6)
        )

        let data = try FolderCoding.makeEncoder().encode(original)
        let decoded = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)

        #expect(decoded.folders.count == 1)
        #expect(decoded.folders.first?.tiles.first?.urlString == "weixin://")
        #expect(decoded.installedSchemes == ["weixin"])
        #expect(decoded.lastProbeAt == original.lastProbeAt)
    }

    @Test("A date that is neither shape is still an error")
    func rejectsGarbageDates() {
        let json = #"{"schemaVersion":1,"folders":[],"lastProbeAt":"last tuesday"}"#
            .data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)
        }
    }

    // MARK: - Missing keys

    /// Schema drift tolerance: a field added in a later version must not discard
    /// the folders that are already there.
    @Test("Absent keys fall back to defaults rather than failing")
    func toleratesAbsentKeys() throws {
        let json = #"{"folders":[{"id":"\#(UUID().uuidString)","name":"工作","colorHex":"","updatedAt":0,"tiles":[]}]}"#
            .data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)

        #expect(library.folders.count == 1)
        #expect(library.schemaVersion == FolderLibrary.currentSchemaVersion)
        #expect(library.probedSchemes.isEmpty)
        #expect(library.lastProbeAt == nil)
    }

    // MARK: - Reachability

    /// The whole point of tracking `probedSchemes` separately: never hide a tile
    /// just because we never asked about it.
    @Test("Only a probed-and-absent scheme counts as unreachable")
    func reachabilityIsConservative() {
        let unprobed = FolderLibrary()
        let tile = FolderTile(title: "微信", urlString: "weixin://")
        #expect(unprobed.isReachable(tile))

        let askedAndMissing = FolderLibrary(installedSchemes: [], probedSchemes: ["weixin"])
        #expect(!askedAndMissing.isReachable(tile))

        let askedAndFound = FolderLibrary(installedSchemes: ["weixin"], probedSchemes: ["weixin"])
        #expect(askedAndFound.isReachable(tile))
    }

    /// `weixin://` stores `weixin`, and the probe records bare lowercased names.
    @Test("Scheme matching ignores case and the //")
    func reachabilityNormalisesScheme() {
        let library = FolderLibrary(
            folders: [],
            installedSchemes: ["weixin"],
            probedSchemes: ["weixin"]
        )
        #expect(library.isReachable(FolderTile(title: "微信", urlString: "weixin://")))
    }

    @Test("A tile that is not a URL is never reachable")
    func rejectsNonURLs() {
        let library = FolderLibrary()
        #expect(!library.isReachable(FolderTile(title: "x", urlString: "")))
    }
}