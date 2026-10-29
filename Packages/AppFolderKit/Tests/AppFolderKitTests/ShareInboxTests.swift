import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Website share inbox")
struct ShareInboxTests {
    @Test("Invalid submissions do not create an inbox or repair a website address")
    func validatesBeforeWriting() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        for url in ["example.com", " https://example.com", "javascript:alert(1)",
                    "https://user:secret@example.com", "https://example.com/%GG", "https://example.com:65536"] {
            #expect(throws: ShareInboxError.invalidURL) { try store.enqueue(url: url) }
        }
        for title in [String(repeating: "a", count: 81), "A\nB", "\tA", "A\u{0000}",
                      String(repeating: " ", count: 513), "a" + String(repeating: "\u{0301}", count: 256)] {
            #expect(throws: ShareInboxError.invalidTitle) { try store.enqueue(url: "https://example.com", title: title) }
        }
        #expect(!FileManager.default.fileExists(atPath: try #require(store.directory).path))
    }

    @Test("Manual titles are bounded and normalized without altering case or fetching a page")
    func titleAndURLBoundaries() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let title = "\u{00A0}  İ i e\u{0301} 中文  \u{00A0}"
        let entry = try store.enqueue(url: "https://bücher.de/Path?Case=Aa#Fragment", title: title)
        #expect(entry.title == "İ i e\u{0301} 中文")
        #expect(entry.url == "https://xn--bcher-kva.de/Path?Case=Aa#Fragment")
        let blank = try store.enqueue(url: "http://localhost:8080/", title: "   ")
        #expect(blank.title == nil)
        let prefix = "https://example.com/"
        let maximumURL = prefix + String(repeating: "a", count: WebsiteURL.maximumUTF8Bytes - prefix.utf8.count)
        let maximum = try store.enqueue(url: maximumURL, title: String(repeating: "\"", count: 80))
        #expect(maximum.url.utf8.count == WebsiteURL.maximumUTF8Bytes)
        #expect(maximum.title?.count == 80)
        #expect(try Data(contentsOf: recordURL(maximum.id, store)).count <= ShareInboxStore.maximumRecordBytes)
        #expect(throws: ShareInboxError.invalidURL) { try store.enqueue(url: maximumURL + "a") }
    }

    @Test("A reload preserves stable import identity and removes only the acknowledged item")
    func stableIdentityAndRemoval() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com", title: "Example")
        let anotherSubmission = try store.enqueue(url: original.url, title: original.title)
        let reloaded: any ShareInboxStorage = ShareInboxRepository(directory: store.directory)
        let snapshot = reloaded.snapshot
        #expect(snapshot.status == .available && snapshot.recordCount == 2)
        #expect(snapshot.entries.contains(original))
        #expect(original.id != anotherSubmission.id, "separate explicit shares are separate pending entries")
        #expect(original.itemID == original.id)
        let destinationIDs: Set<UUID> = [original.itemID]
        #expect(snapshot.entries.filter { destinationIDs.contains($0.itemID) } == [original])
        // A failed/cancelled destination save need not call remove at all.
        #expect(reloaded.snapshot.entries.contains(original))
        #expect(try reloaded.remove(id: original.id))
        #expect(try !reloaded.remove(id: original.id))
        #expect(reloaded.snapshot.entries == [anotherSubmission])
    }

    @Test("Removing a matching snapshot and restoring it preserves every field and the original bytes")
    func matchingRemovalAndUndo() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com/Case?x=Aa#Part", title: "Cafe\u{0301} 中文",
                                         id: UUID(), createdAt: Date(timeIntervalSinceReferenceDate: 12345.125))
        let other = try store.enqueue(url: "https://example.org")
        let bytes = try Data(contentsOf: recordURL(original.id, store))
        let otherBytes = try Data(contentsOf: recordURL(other.id, store))
        #expect(try store.remove(ifMatching: original))
        #expect(try !store.remove(ifMatching: original), "an already absent entry must not create a new undo claim")
        #expect(store.snapshot.entries == [other])
        let reopened = ShareInboxRepository(directory: store.directory)
        try reopened.restore(original)
        #expect(reopened.snapshot.entries.contains(original))
        #expect(try Data(contentsOf: recordURL(original.id, store)) == bytes)
        #expect(try Data(contentsOf: recordURL(other.id, store)) == otherBytes)
        #expect(try reopened.remove(ifMatching: original))
    }

    @Test("Restoring into a missing inbox preserves a boundary-sized URL and title without creating new identity")
    func restoresFirstUseWithBoundedRecord() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "https://example.com/"
        let address = prefix + String(repeating: "a", count: WebsiteURL.maximumUTF8Bytes - prefix.utf8.count)
        let entry = try ShareInboxEntry(id: UUID(), url: address, title: String(repeating: "🌐", count: 80),
                                       createdAt: Date(timeIntervalSinceReferenceDate: 12345.125))
        #expect(try !store.remove(ifMatching: entry))
        #expect(!FileManager.default.fileExists(atPath: try #require(store.directory).path))
        try store.restore(entry)
        #expect(store.snapshot.entries == [entry])
        #expect(try Data(contentsOf: recordURL(entry.id, store)).count <= ShareInboxStore.maximumRecordBytes)
    }

    @Test("Matching deletion and restore refuse a changed URL, title or creation time without touching it")
    func undoConflictsPreserveExisting() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com", title: "Original")
        let bytes = try Data(contentsOf: recordURL(original.id, store))
        let variants = [
            try ShareInboxEntry(id: original.id, url: "https://example.org", title: original.title, createdAt: original.createdAt),
            try ShareInboxEntry(id: original.id, url: original.url, title: "Changed", createdAt: original.createdAt),
            try ShareInboxEntry(id: original.id, url: original.url, title: original.title, createdAt: original.createdAt.addingTimeInterval(1))
        ]
        for changed in variants {
            #expect(throws: ShareInboxError.recordAlreadyExists) { try store.remove(ifMatching: changed) }
            #expect(throws: ShareInboxError.recordAlreadyExists) { try store.restore(changed) }
            #expect(try Data(contentsOf: recordURL(original.id, store)) == bytes)
        }
        // The snapshot was genuinely removed, but another process reused its ID.
        #expect(try store.remove(ifMatching: original))
        let replacement = try #require(variants.first)
        try store.restore(replacement)
        let replacementBytes = try Data(contentsOf: recordURL(original.id, store))
        #expect(throws: ShareInboxError.recordAlreadyExists) { try store.restore(original) }
        #expect(try Data(contentsOf: recordURL(original.id, store)) == replacementBytes)
    }

    @Test("Undo is idempotent in a full queue but a missing entry cannot displace another submission")
    func restoreCapacityAndIdempotency() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com", title: "Undo")
        for _ in 1..<ShareInboxStore.maximumEntries {
            try Data("bad but capacity-occupying".utf8).write(to: recordURL(UUID(), store))
        }
        let before = store.snapshot
        let file = recordURL(original.id, store)
        var info = stat()
        #expect(lstat(file.path, &info) == 0)
        try store.restore(original)
        var afterInfo = stat()
        #expect(lstat(file.path, &afterInfo) == 0)
        #expect(info.st_ino == afterInfo.st_ino, "an identical retry must not rewrite the entry")
        #expect(store.snapshot == before)
        #expect(try store.remove(ifMatching: original))
        let later = try store.enqueue(url: "https://example.org")
        let full = store.snapshot
        #expect(throws: ShareInboxError.full) { try store.restore(original) }
        #expect(store.snapshot == full && store.snapshot.entries == [later])
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try store.remove(id: later.id))
        try store.restore(original)
        #expect(store.snapshot == before)
    }

    @Test("Unreadable or misidentified records cannot be erased or repaired by remove and undo")
    func undoRejectsDamage() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com")
        let another = try store.enqueue(url: "https://example.org")
        let file = recordURL(original.id, store)
        let wrongIdentity = try Data(contentsOf: recordURL(another.id, store))
        for bytes in [Data(), Data("bad JSON".utf8),
                      Data(repeating: 32, count: ShareInboxStore.maximumRecordBytes + 1), wrongIdentity] {
            try bytes.write(to: file)
            #expect(throws: ShareInboxError.storageFailure) { try store.remove(ifMatching: original) }
            #expect(throws: ShareInboxError.storageFailure) { try store.restore(original) }
            #expect(try Data(contentsOf: file) == bytes)
        }
        // Keep the prior acknowledgement API's ability to remove a damaged ID.
        #expect(try store.remove(id: original.id))
        #expect(store.snapshot.entries == [another])
    }

    @Test("Removal and undo do not follow record links or replace nonregular records")
    func undoRejectsLinksAndNonregularRecords() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try store.enqueue(url: "https://example.com")
        let file = recordURL(entry.id, store)
        let bytes = try Data(contentsOf: file)
        #expect(try store.remove(ifMatching: entry))
        let outside = root.appendingPathComponent("outside.json")
        try bytes.write(to: outside)
        for kind in ["symlink", "hardlink", "fifo", "directory"] {
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
            case "hardlink": try FileManager.default.linkItem(at: outside, to: file)
            case "fifo": #expect(mkfifo(file.path, S_IRUSR | S_IWUSR) == 0)
            default: try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            }
            var before = stat()
            #expect(lstat(file.path, &before) == 0)
            #expect(throws: ShareInboxError.storageFailure) { try store.remove(ifMatching: entry) }
            #expect(throws: ShareInboxError.storageFailure) { try store.restore(entry) }
            var after = stat()
            #expect(lstat(file.path, &after) == 0)
            #expect(before.st_ino == after.st_ino && before.st_mode == after.st_mode)
            #expect(try Data(contentsOf: outside) == bytes)
            try FileManager.default.removeItem(at: file)
        }
    }

    @Test("Unavailable, first-use and unreadable directory states cannot masquerade as one another")
    func directoryStates() throws {
        let unavailable = ShareInboxRepository(directory: nil)
        #expect(unavailable.snapshot.status == .unavailable)
        #expect(!unavailable.snapshot.isAvailable && !unavailable.snapshot.isEmpty)
        #expect(throws: ShareInboxError.unavailable) { try unavailable.enqueue(url: "https://example.com") }
        #expect(throws: ShareInboxError.unavailable) { try unavailable.remove(id: UUID()) }
        let entry = try ShareInboxEntry(id: UUID(), url: "https://example.com", title: nil, createdAt: .now)
        #expect(throws: ShareInboxError.unavailable) { try unavailable.remove(ifMatching: entry) }
        #expect(throws: ShareInboxError.unavailable) { try unavailable.restore(entry) }
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(store.directory)
        #expect(store.snapshot.isEmpty)
        #expect(try !store.remove(id: UUID()))
        #expect(try !store.remove(ifMatching: entry))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let bytes = Data("not a directory".utf8)
        try bytes.write(to: directory)
        #expect(store.snapshot.status == .directoryFailure)
        #expect(!store.snapshot.isEmpty)
        #expect(throws: ShareInboxError.storageFailure) { try store.enqueue(url: "https://example.com") }
        #expect(try Data(contentsOf: directory) == bytes)
    }

    @Test("Corrupt, future, oversized and nonregular records remain visible as failures without deletion")
    func partialSnapshotPreservesRecords() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = try store.enqueue(url: "https://example.com", title: "Readable")
        let directory = try #require(store.directory)
        let goodBytes = try Data(contentsOf: recordURL(good.id, store))
        let object = try #require(JSONSerialization.jsonObject(with: goodBytes) as? [String: Any])
        var files: [(URL, Data)] = []
        for mutation in ["version", "url", "title", "unknown"] {
            var bad = object
            let id = UUID()
            bad["id"] = id.uuidString
            switch mutation {
            case "version": bad["version"] = 2
            case "url": bad["url"] = "example.com"
            case "title": bad["title"] = " noncanonical "
            default: bad["unknown"] = "ignored by a permissive decoder"
            }
            files.append((recordURL(id, store), try JSONSerialization.data(withJSONObject: bad)))
        }
        files.append((recordURL(UUID(), store), Data("not JSON".utf8)))
        files.append((recordURL(UUID(), store), Data(repeating: 32, count: ShareInboxStore.maximumRecordBytes + 1)))
        files.append((recordURL(UUID(), store), goodBytes)) // filename/identity mismatch
        files.append((directory.appendingPathComponent("unexpected.json"), goodBytes))
        for (url, bytes) in files { try bytes.write(to: url) }
        let folder = recordURL(UUID(), store)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let fifo = recordURL(UUID(), store)
        #expect(mkfifo(fifo.path, S_IRUSR | S_IWUSR) == 0)
        let snapshot = store.snapshot
        #expect(snapshot.status == .available)
        #expect(snapshot.entries == [good])
        #expect(snapshot.unreadableCount == files.count + 2)
        #expect(snapshot.recordCount == files.count + 3)
        #expect(snapshot.hasReadFailures && !snapshot.isEmpty)
        for (url, bytes) in files { #expect(try Data(contentsOf: url) == bytes) }
        #expect(try Data(contentsOf: recordURL(good.id, store)) == goodBytes)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(FileManager.default.fileExists(atPath: fifo.path))
    }

    @Test("A damaged record occupies capacity and a full inbox never evicts a pending entry")
    func capacityIncludesDamage() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try store.enqueue(url: "https://example.com")
        for _ in 1..<ShareInboxStore.maximumEntries {
            try Data("bad record".utf8).write(to: recordURL(UUID(), store))
        }
        let before = store.snapshot
        #expect(before.recordCount == ShareInboxStore.maximumEntries)
        #expect(before.entries == [first] && before.unreadableCount == 99)
        #expect(throws: ShareInboxError.full) { try store.enqueue(url: "https://example.org") }
        #expect(store.snapshot == before)
        #expect(try store.remove(id: first.id))
        let later = try store.enqueue(url: "https://example.org")
        #expect(store.snapshot.entries == [later])
        #expect(store.snapshot.recordCount == ShareInboxStore.maximumEntries)
        try Data("external extra record".utf8).write(to: recordURL(UUID(), store))
        #expect(store.snapshot.status == .overCapacity)
        #expect(store.snapshot.recordCount == ShareInboxStore.maximumEntries + 1)
        #expect(!store.snapshot.isEmpty, "an over-limit directory must not be displayed as an empty inbox")
    }

    @Test("A stable ID collision cannot overwrite even an unreadable original")
    func rejectsCollisions() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com")
        let file = recordURL(original.id, store)
        let originalBytes = try Data(contentsOf: file)
        #expect(throws: ShareInboxError.recordAlreadyExists) {
            try store.enqueue(url: "https://example.org", title: nil, id: original.id, createdAt: .now)
        }
        #expect(try Data(contentsOf: file) == originalBytes)
        let corrupt = Data("keep these original bytes".utf8)
        try corrupt.write(to: file)
        #expect(throws: ShareInboxError.recordAlreadyExists) {
            try store.enqueue(url: "https://example.org", title: nil, id: original.id, createdAt: .now)
        }
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test("Symlinked records and directories are not followed for reading, writing or removal")
    func rejectsSymlinks() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = try store.enqueue(url: "https://example.com")
        let id = UUID()
        let outside = root.appendingPathComponent("outside.json")
        let bytes = try Data(contentsOf: recordURL(good.id, store))
        try bytes.write(to: outside)
        let link = recordURL(id, store)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(store.snapshot.entries == [good])
        #expect(store.snapshot.unreadableCount == 1)
        #expect(throws: ShareInboxError.storageFailure) { try store.remove(id: id) }
        #expect(try Data(contentsOf: outside) == bytes)
        let directoryLink = root.appendingPathComponent("linked-inbox")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: try #require(store.directory))
        let linked = ShareInboxRepository(directory: directoryLink)
        #expect(linked.snapshot.status == .directoryFailure)
        #expect(throws: ShareInboxError.storageFailure) { try linked.enqueue(url: "https://example.org") }
        #expect(throws: ShareInboxError.storageFailure) { try linked.remove(id: good.id) }
        #expect(store.snapshot.entries == [good])
    }

    @Test("A symlink, FIFO or hard link cannot stand in for the cross-process lock file")
    func validatesLockFile() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sentinel = root.appendingPathComponent("sentinel")
        let bytes = Data("untouched".utf8)
        try bytes.write(to: sentinel)
        let lock = directory.appendingPathComponent(ShareInboxRepository.lockFilename)
        for kind in ["symlink", "fifo", "hardlink"] {
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: sentinel)
            case "fifo": #expect(mkfifo(lock.path, S_IRUSR | S_IWUSR) == 0)
            default: try FileManager.default.linkItem(at: sentinel, to: lock)
            }
            #expect(store.snapshot.status == .directoryFailure)
            #expect(throws: ShareInboxError.storageFailure) { try store.enqueue(url: "https://example.com") }
            #expect(try Data(contentsOf: sentinel) == bytes)
            try FileManager.default.removeItem(at: lock)
        }
        #expect(store.snapshot.isEmpty)
    }

    @Test("Shared readers coexist and mutations return busy while a reader holds the lock")
    func readLockExcludesMutations() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try store.enqueue(url: "https://example.com")
        let lockURL = try #require(store.directory).appendingPathComponent(ShareInboxRepository.lockFilename)
        let descriptor = open(lockURL.path, O_RDONLY)
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_SH | LOCK_NB) == 0)
        #expect(store.snapshot.entries == [entry])
        #expect(throws: ShareInboxError.busy) { try store.enqueue(url: "https://example.org") }
        #expect(throws: ShareInboxError.busy) { try store.remove(id: entry.id) }
        #expect(throws: ShareInboxError.busy) { try store.remove(ifMatching: entry) }
        #expect(throws: ShareInboxError.busy) { try store.restore(entry) }
        #expect(flock(descriptor, LOCK_UN) == 0)
        #expect(try store.remove(id: entry.id))
    }

    #if os(macOS)
    @Test("An independent process excludes App operations and a crash releases its lock")
    func independentProcessLockAndCrash() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try store.enqueue(url: "https://example.com")
        let originalBytes = try Data(contentsOf: recordURL(original.id, store))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", "import fcntl,sys; f=open(sys.argv[1],'r+'); fcntl.flock(f,fcntl.LOCK_EX); sys.stdout.buffer.write(b'1'); sys.stdout.flush(); sys.stdin.buffer.read(1)",
                           try #require(store.directory).appendingPathComponent(ShareInboxRepository.lockFilename).path]
        let output = Pipe(), input = Pipe()
        child.standardOutput = output
        child.standardInput = input
        child.standardError = Pipe()
        try child.run()
        defer {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        #expect(try output.fileHandleForReading.read(upToCount: 1) == Data("1".utf8))
        #expect(store.snapshot.status == .busy)
        #expect(!store.snapshot.isEmpty)
        #expect(throws: ShareInboxError.busy) { try store.enqueue(url: "https://example.org") }
        #expect(throws: ShareInboxError.busy) { try store.remove(id: original.id) }
        #expect(throws: ShareInboxError.busy) { try store.remove(ifMatching: original) }
        #expect(throws: ShareInboxError.busy) { try store.restore(original) }
        child.terminate()
        child.waitUntilExit()
        let next = try store.enqueue(url: "https://example.org")
        #expect(Set(store.snapshot.entries.map(\.id)) == [original.id, next.id])
        #expect(try Data(contentsOf: recordURL(original.id, store)) == originalBytes)
        try store.restore(original)
    }
    #endif

    @Test("Concurrent repositories cannot exceed capacity or expose partially written records")
    func concurrentEnqueues() async throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<(ShareInboxStore.maximumEntries - 5) {
            _ = try store.enqueue(url: "https://example.com/old/\(index)")
        }
        let created = try await withThrowingTaskGroup(of: ShareInboxEntry?.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let independent = ShareInboxRepository(directory: store.directory)
                    for _ in 0..<500 {
                        do { return try independent.enqueue(url: "https://example.com/new/\(index)") }
                        catch ShareInboxError.full { return nil }
                        catch ShareInboxError.busy { try await Task.sleep(for: .milliseconds(2)) }
                    }
                    throw ShareInboxError.busy
                }
            }
            group.addTask {
                for _ in 0..<30 {
                    let snapshot = ShareInboxRepository(directory: store.directory).snapshot
                    #expect(snapshot.status == .available || snapshot.status == .busy)
                    if snapshot.status == .available {
                        #expect(snapshot.unreadableCount == 0)
                        #expect(snapshot.entries.count == snapshot.recordCount)
                        #expect(snapshot.recordCount <= ShareInboxStore.maximumEntries)
                    }
                    await Task.yield()
                }
                return nil
            }
            var created: [ShareInboxEntry] = []
            for try await entry in group { if let entry { created.append(entry) } }
            return created
        }
        #expect(created.count == 5)
        #expect(Set(created.map(\.id)).count == 5)
        #expect(store.snapshot.recordCount == ShareInboxStore.maximumEntries)
        #expect(store.snapshot.unreadableCount == 0)
        #expect(created.allSatisfy { store.snapshot.entries.contains($0) })
    }

    private func repository() throws -> (ShareInboxRepository, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("appfolder-share-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (ShareInboxRepository(directory: root.appendingPathComponent("WebShareInbox", isDirectory: true)), root)
    }

    private func recordURL(_ id: UUID, _ store: ShareInboxRepository) -> URL {
        store.directory!.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }
}
