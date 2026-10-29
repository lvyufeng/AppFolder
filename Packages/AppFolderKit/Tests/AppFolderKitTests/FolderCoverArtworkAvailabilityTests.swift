import Testing
@testable import AppFolderKit

@Suite("Folder cover artwork availability")
struct FolderCoverArtworkAvailabilityTests {
    private let standardID = FolderCoverAssetID(rawValue: String(repeating: "a", count: 64))!
    private let darkID = FolderCoverAssetID(rawValue: String(repeating: "b", count: 64))!

    @Test("Intentional inherited and automatic appearances do not request retries")
    func intentionalFallbacks() throws {
        let icon = try #require(CustomIcon.symbol("star.fill"))
        let standardOnly = FolderCover(standard: standardID)
        let darkOnly = FolderCover(dark: darkID)
        let inheritedDarkNeedsRetry = standardOnly.hasMissingArtwork(in: .init(standard: icon))
        let automaticStandardNeedsRetry = darkOnly.hasMissingArtwork(in: .init(dark: icon))
        #expect(!inheritedDarkNeedsRetry)
        #expect(!automaticStandardNeedsRetry)
    }

    @Test("Either missing explicit appearance requests a retry despite a usable fallback")
    func partiallyLoadedCover() throws {
        let icon = try #require(CustomIcon.symbol("star.fill"))
        let cover = FolderCover(standard: standardID, dark: darkID)
        let missingDark = cover.hasMissingArtwork(in: .init(standard: icon))
        let missingStandard = cover.hasMissingArtwork(in: .init(dark: icon))
        let complete = cover.hasMissingArtwork(in: .init(standard: icon, dark: icon))
        #expect(missingDark)
        #expect(missingStandard)
        #expect(!complete)
    }

    @Test("Missing all artwork is distinct from an intentional absent appearance")
    func missingReads() {
        #expect(FolderCover(standard: standardID).hasMissingArtwork(in: nil))
        #expect(FolderCover(dark: darkID).hasMissingArtwork(in: nil))
        #expect(FolderCover(standard: standardID, dark: darkID).hasMissingArtwork(in: nil))
    }
}
