import Foundation
import Testing

@testable import AppFolderKit

/// The choice between the App Group and the `UserDefaults` fallback.
///
/// This is the bug that cost the user 分享 App on 2026-10-02: a write that did
/// not reach the group fell back to `UserDefaults` silently, the app and the
/// widget read different libraries from then on, and every subsequent share was
/// deposited against a folder id the app no longer had — and dropped. Nothing
/// failed loudly, which is exactly what made it take a day to find.
///
/// The store cannot be pointed at a test container, so these tests pin the
/// decisions that do not need one: which of two libraries wins, and what
/// "newer" means.
@Suite("Folder store")
struct FolderStoreTests {
    private func library(folderUpdated: Date, probed: Date? = nil) -> FolderLibrary {
        FolderLibrary(
            folders: [
                Folder(name: "常用", tiles: [], updatedAt: folderUpdated)
            ],
            lastProbeAt: probed
        )
    }

    /// The winner is the newest thing in the library, not the top-level folder.
    ///
    /// The case that matters: the app forked to `UserDefaults` at time T, so the
    /// group's file is frozen at T while the fallback keeps moving. Both exist on
    /// the next launch, and taking the group's copy would throw away everything
    /// the user did in between — silently, on the launch meant to repair it.
    @Test("The newer library wins, whichever side it came from")
    func newerLibraryWins() {
        let older = library(folderUpdated: Date(timeIntervalSince1970: 1_000))
        let newer = library(folderUpdated: Date(timeIntervalSince1970: 2_000))
        #expect(FolderStore.newer(older, newer).folders.first?.updatedAt == newer.folders.first?.updatedAt)
        #expect(FolderStore.newer(newer, older).folders.first?.updatedAt == newer.folders.first?.updatedAt)
    }

    /// A probe is an edit too. The app rewrites `lastProbeAt` on every launch, so
    /// ignoring it would make a library whose folders are old look staler than one
    /// whose folders are equally old — and pick wrongly.
    @Test("A fresh probe counts as freshness")
    func probeCounts() {
        let folderOnly = library(folderUpdated: Date(timeIntervalSince1970: 2_000))
        let probed = library(
            folderUpdated: Date(timeIntervalSince1970: 1_000),
            probed: Date(timeIntervalSince1970: 3_000)
        )
        #expect(FolderStore.newer(folderOnly, probed).lastProbeAt != nil)
    }

    /// Neither copy exists — a first run. Not a crash, and not a tie broken by
    /// accident: an empty library either way.
    @Test("Two empty libraries resolve to empty")
    func emptyResolveEmpty() {
        let winner = FolderStore.newer(.empty, .empty)
        #expect(winner.folders.isEmpty)
    }
}