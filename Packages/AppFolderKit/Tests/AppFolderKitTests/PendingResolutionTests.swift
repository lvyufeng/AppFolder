import Foundation
import Testing

@testable import AppFolderKit

/// The queue of shared-in apps waiting for a launch target.
///
/// Driven against a temporary directory rather than the App Group container, which
/// a test host cannot reach — see ``PendingResolutionStore/init(directoryURL:)``.
/// The encode/decode/sort/remove logic is the real one either way.
@Suite("Pending resolutions")
struct PendingResolutionTests {
    /// A store over a fresh empty directory, with a cleanup that runs even if a
    /// case fails.
    private func withStore(_ body: (PendingResolutionStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pending-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(PendingResolutionStore(directoryURL: root), root)
    }

    private func record(
        trackID: Int = 414478124,
        region: String? = nil,
        folderID: UUID = UUID()
    ) -> PendingResolution {
        PendingResolution(trackID: trackID, region: region, folderID: folderID)
    }

    /// The round trip a share actually takes: deposit, then read back with
    /// everything intact. A field lost here is a folder the confirmation cannot
    /// find or a lookup against the wrong storefront.
    @Test("A deposited record comes back whole")
    func roundTrip() throws {
        try withStore { store, _ in
            let folder = UUID()
            let item = record(trackID: 1052455390, region: "cn", folderID: folder)
            #expect(store.deposit(item))

            let all = store.all()
            #expect(all.count == 1)
            let read = try #require(all.first)
            #expect(read.id == item.id)
            #expect(read.trackID == 1052455390)
            #expect(read.region == "cn")
            #expect(read.folderID == folder)
        }
    }

    /// Every shared app is its own file, so two deposits cannot collide and
    /// neither has to read the directory first. This is the property that makes
    /// the extension safe; here it is what makes two shares in a row survive.
    @Test("Two records coexist and are all returned")
    func twoRecordsCoexist() throws {
        try withStore { store, _ in
            #expect(store.deposit(record(trackID: 1)))
            #expect(store.deposit(record(trackID: 2)))

            #expect(store.all().count == 2)
            #expect(Set(store.all().map(\.trackID)) == [1, 2])
        }
    }

    /// Oldest first, so the editor lists them in the order they were shared. The
    /// order is not cosmetic: the user recognises "the one I just did" by position
    /// when the names have not loaded yet.
    @Test("Records come back oldest first")
    func oldestFirst() throws {
        try withStore { store, _ in
            let base = Date(timeIntervalSince1970: 1_000_000)
            let older = PendingResolution(trackID: 1, region: nil, folderID: UUID(), addedAt: base)
            let newer = PendingResolution(trackID: 2, region: nil, folderID: UUID(), addedAt: base.addingTimeInterval(60))
            // Deposited newest-first, so the sort has something to do.
            _ = store.deposit(newer)
            _ = store.deposit(older)

            #expect(store.all().map(\.trackID) == [1, 2])
        }
    }

    /// The badge is a *look*, and looking must not consume. If `all()` drained,
    /// the count would depend on how many times the screen was opened — and the
    /// first reader would silently take the user's queue away.
    @Test("Reading the queue does not consume it")
    func readingIsNonDestructive() throws {
        try withStore { store, _ in
            _ = store.deposit(record())
            _ = store.all()
            _ = store.count()
            #expect(store.all().count == 1)
        }
    }

    /// ``PendingResolutionStore/count()`` is what the badge shows, and it counts by
    /// file name rather than by decoding — so it has to agree with `all()` for
    /// well-formed records.
    @Test("The count matches the records")
    func countMatchesRecords() throws {
        try withStore { store, _ in
            #expect(store.count() == 0)
            _ = store.deposit(record(trackID: 1))
            _ = store.deposit(record(trackID: 2))
            _ = store.deposit(record(trackID: 3))

            #expect(store.count() == 3)
            #expect(store.count() == store.all().count)
        }
    }

    /// Confirming or discarding one entry removes exactly that one, by id.
    @Test("Removing one leaves the others")
    func removeIsSurgical() throws {
        try withStore { store, _ in
            let first = record(trackID: 1)
            let second = record(trackID: 2)
            _ = store.deposit(first)
            _ = store.deposit(second)

            store.remove(first.id)

            #expect(store.all().map(\.trackID) == [2])
            #expect(store.count() == 1)
        }
    }

    /// Removing by id is why a record this build cannot decode can still be
    /// cleared. The alternative — an entry that can never leave the queue — is a
    /// badge that never goes down, with nothing the user can do about it.
    @Test("A record that cannot be decoded can still be removed")
    func undecodableRecordCanBeCleared() throws {
        try withStore { store, root in
            _ = store.deposit(record(trackID: 1))
            // A file with the right shape and the wrong contents, which is what a
            // future schema change looks like to this build.
            let broken = UUID()
            try Data("{\"not\":\"a record\"}".utf8)
                .write(to: root.appending(path: "\(broken.uuidString).json"))

            #expect(store.all().count == 1)      // the broken one is skipped
            #expect(store.count() == 2)          // but still counted

            store.remove(broken)

            #expect(store.all().count == 1)
            #expect(store.count() == 1)
        }
    }

    /// Nothing waiting is nothing to show — and the badge's zero is the documented
    /// way to clear it, so this is the state that takes the numeral off the icon.
    @Test("An empty queue reads as zero")
    func emptyQueueIsZero() throws {
        try withStore { store, _ in
            #expect(store.all().isEmpty)
            #expect(store.count() == 0)
            // Removing something that is not there is a no-op, not a crash: the
            // editor can confirm an entry twice if a tap lands twice.
            store.remove(UUID())
            #expect(store.count() == 0)
        }
    }

    /// A record carries only what the link carried, and that is load-bearing: the
    /// name and icon are resolved later, so an offline share **waits** instead of
    /// being dropped. This asserts the shape that makes that possible.
    @Test("A record needs only the track id and a folder")
    func recordNeedsNoResolvedMetadata() throws {
        try withStore { store, _ in
            _ = store.deposit(record(trackID: 42, region: nil, folderID: UUID()))
            let read = try #require(store.all().first)
            #expect(read.trackID == 42)
            #expect(read.region == nil)
        }
    }
}