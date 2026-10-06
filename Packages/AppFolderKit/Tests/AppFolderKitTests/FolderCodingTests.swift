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

    /// The same guarantee one level down, and the one that is easy to lose.
    ///
    /// `FolderLibrary` has hand-written lenient decoding and always will; `Folder`
    /// had *synthesized* `Codable` until `plate` and `showsTitles` were added to
    /// it. Synthesized decoding ignores property defaults when a key is absent,
    /// so `plate` — a non-optional enum — would have failed the whole decode of
    /// any library written before it existed. That is not a missing setting: it is
    /// ``FolderStore`` moving the file aside as `.corrupt` and starting empty, on
    /// every device that had ever used the app.
    ///
    /// Written as the literal bytes an older version would have produced, rather
    /// than by encoding a `Folder` and stripping keys, so the test cannot be
    /// satisfied by the encoder and decoder drifting together.
    @Test("A folder written before the plate existed still decodes")
    func folderToleratesAbsentAppearanceKeys() throws {
        let json = """
        {
          "folders": [
            {
              "id": "\(UUID().uuidString)",
              "name": "常用",
              "colorHex": "",
              "updatedAt": 812104549.6,
              "tiles": [
                {"id":"\(UUID().uuidString)","kind":"app","title":"微信","urlString":"weixin://","strategy":"bounce"}
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)
        let folder = try #require(library.folders.first)

        #expect(folder.name == "常用")
        #expect(folder.tiles.count == 1, "the tiles are the thing that would be lost")
        #expect(folder.plate == .automatic, "an unset plate must mean the system's")
        #expect(folder.showsTitles == false, "labels were off before this field existed")
    }

    /// The same guarantee for the tile, which is where the newest field landed.
    ///
    /// `FolderTile` had synthesized `Codable` until `needsSchemeConfirmation` was
    /// added. A `Bool` has no absent-key tolerance under synthesis — `decode`
    /// throws where `decodeIfPresent` would not — so adding it would have failed
    /// the decode of every library written before it, and ``FolderStore`` answers
    /// a failed decode by quarantining the file. One boolean would have cost the
    /// user every folder, so the test is written against the literal bytes an
    /// older build produced rather than against a round trip.
    @Test("A tile written before the confirmation flag still decodes")
    func tileToleratesAbsentConfirmationFlag() throws {
        let json = """
        {
          "folders": [
            {
              "id": "\(UUID().uuidString)",
              "name": "常用",
              "colorHex": "",
              "updatedAt": 812104549.6,
              "tiles": [
                {
                  "id": "\(UUID().uuidString)",
                  "kind": "app",
                  "title": "票牛",
                  "urlString": "pner://",
                  "appStoreID": 1052455390,
                  "strategy": "bounce"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)
        let tile = try #require(library.folders.first?.tiles.first)

        #expect(tile.title == "票牛")
        #expect(tile.urlString == "pner://", "the scheme is the thing that would be lost")
        #expect(tile.needsSchemeConfirmation == false, "a tile from before the flag carries no warning")
        #expect(tile.bundleID == nil)
    }

    /// ``FolderTile/bundleID`` is new, and it is the field that lets a later
    /// improvement to ``SchemeGuess`` re-derive a scheme for a tile that is
    /// already saved. If it does not survive a write it can never do that.
    @Test("The bundle id and the confirmation flag round-trip")
    func tileGuessFieldsRoundTrip() throws {
        let original = FolderLibrary(folders: [
            Folder(name: "常用", tiles: [
                FolderTile(
                    title: "票牛",
                    scheme: "pner://",
                    appStoreID: 1052455390,
                    bundleID: "com.ipiaoniu.pner",
                    needsSchemeConfirmation: true
                ),
            ]),
        ])

        let decoded = try FolderCoding.makeDecoder()
            .decode(FolderLibrary.self, from: FolderCoding.makeEncoder().encode(original))
        let tile = try #require(decoded.folders.first?.tiles.first)

        #expect(tile.bundleID == "com.ipiaoniu.pner")
        #expect(tile.needsSchemeConfirmation)
    }

    /// The collapse request has to survive a write, or the app's request to close
/// an expanded widget never reaches the widget.
    ///
    /// It defaults to zero, which is what a library written before it decodes to
    /// — and the widget's own cursor starts at zero too, so upgrading does not
    /// spuriously collapse anything.
    @Test("The collapse request round-trips and defaults to zero")
    func collapseRequestRoundTrips() throws {
        let old = #"{"folders":[]}"#.data(using: .utf8)!
        #expect(try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: old).collapseRequest == 0)

        var library = FolderLibrary()
        library.collapseRequest = 3
        let decoded = try FolderCoding.makeDecoder()
            .decode(FolderLibrary.self, from: FolderCoding.makeEncoder().encode(library))
        #expect(decoded.collapseRequest == 3)
    }

    /// A field the *encoder* writes has to survive the decoder, and the reverse.
    @Test("The appearance fields round-trip")
    func roundTripsAppearance() throws {
        let original = FolderLibrary(folders: [
            Folder(
                name: "工作",
                tiles: [FolderTile(title: "微信", urlString: "weixin://")],
                colorHex: "#3478F6",
                plate: .gradient,
                showsTitles: true
            )
        ])

        let data = try FolderCoding.makeEncoder().encode(original)
        let decoded = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: data)
        let folder = try #require(decoded.folders.first)

        #expect(folder.colorHex == "#3478F6")
        #expect(folder.plate == .gradient)
        #expect(folder.showsTitles == true)
    }

    /// An unknown plate name — a folder written by a *newer* build, or hand-edited
    /// — must not take the library with it either. Falling back to `automatic` is
    /// the conservative direction: it draws nothing, so the worst case is a folder
    /// that looks like it always did.
    @Test("An unrecognised plate falls back rather than failing")
    func unknownPlateFallsBack() throws {
        let json = #"{"folders":[{"id":"\#(UUID().uuidString)","name":"工作","colorHex":"","plate":"holographic","updatedAt":0,"tiles":[]}]}"#
            .data(using: .utf8)!

        let library = try FolderCoding.makeDecoder().decode(FolderLibrary.self, from: json)

        #expect(library.folders.first?.plate == .automatic)
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