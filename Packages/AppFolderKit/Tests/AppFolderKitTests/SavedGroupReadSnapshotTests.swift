import Foundation
import Testing
@testable import AppFolderKit

@Suite("Saved group read reports")
struct SavedGroupReadSnapshotTests {
    @Test("Unavailable containers are distinct from empty available libraries")
    func unavailableContainer() {
        let snapshot = SavedGroupRepository(directory: nil).snapshot
        #expect(!snapshot.isAvailable)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.unreadableCount == 0)
        #expect(!snapshot.directoryFailure)
        #expect(!snapshot.hasReadFailures)
    }

    @Test("A first-use directory is empty without creating files")
    func missingDirectory() throws {
        try withRepository { repository, directory in
            let snapshot = repository.snapshot
            #expect(snapshot.isAvailable)
            #expect(snapshot.groups.isEmpty)
            #expect(!snapshot.hasReadFailures)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }
    }

    @Test("A real empty directory and unrelated files do not report lost groups")
    func emptyDirectory() throws {
        try withRepository { repository, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let unrelated = directory.appendingPathComponent("notes.txt")
            let bytes = Data("unrelated file".utf8)
            try bytes.write(to: unrelated)
            let snapshot = repository.snapshot
            #expect(snapshot.isAvailable)
            #expect(snapshot.groups.isEmpty)
            #expect(!snapshot.hasReadFailures)
            #expect(try Data(contentsOf: unrelated) == bytes)
        }
    }

    @Test("A non-directory path reports enumeration failure without overwriting it")
    func directoryFailure() throws {
        try withRepository { repository, directory in
            let bytes = Data("this path is a file".utf8)
            try bytes.write(to: directory)
            let snapshot = repository.snapshot
            #expect(snapshot.isAvailable)
            #expect(snapshot.directoryFailure)
            #expect(snapshot.hasReadFailures)
            #expect(snapshot.unreadableCount == 0)
            #expect(snapshot.groups.isEmpty)
            #expect(repository.all.isEmpty)
            #expect(try Data(contentsOf: directory) == bytes)

            // A later retry re-reads the directory rather than caching failure.
            try FileManager.default.removeItem(at: directory)
            let restored = SavedGroup(name: "Recovered")
            #expect(repository.save(restored))
            #expect(repository.snapshot.groups == [restored])
            #expect(!repository.snapshot.hasReadFailures)
        }
    }

    @Test("Malformed records are counted while readable groups remain sorted and unchanged")
    func mixedReadableAndUnreadableRecords() throws {
        try withRepository { repository, directory in
            var older = SavedGroup(name: "Older")
            older.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
            var newer = SavedGroup(name: "Newer", items: [.website(name: "Example", url: "https://example.com")])
            newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
            #expect(repository.save(older))
            #expect(repository.save(newer))

            let badFiles: [(URL, Data)] = [
                (recordURL(in: directory), Data("not JSON".utf8)),
                (recordURL(in: directory), Data(repeating: 0, count: SavedGroupRepository.maximumFileBytes + 1)),
                // Valid JSON under another group's filename is still unreadable.
                (recordURL(in: directory), try JSONEncoder().encode(older)),
            ]
            for (url, data) in badFiles { try data.write(to: url) }
            let nonRegular = recordURL(in: directory)
            try FileManager.default.createDirectory(at: nonRegular, withIntermediateDirectories: false)
            let goodURLs = [older, newer].map { directory.appendingPathComponent($0.id.uuidString.lowercased() + ".json") }
            let before = try goodURLs.map { try Data(contentsOf: $0) }

            let snapshot = repository.snapshot
            #expect(snapshot.isAvailable)
            #expect(!snapshot.directoryFailure)
            #expect(snapshot.hasReadFailures)
            #expect(snapshot.unreadableCount == 4)
            #expect(snapshot.groups == [newer, older])
            #expect(repository.all == snapshot.groups)
            #expect(try goodURLs.map { try Data(contentsOf: $0) } == before)
            for (url, data) in badFiles { #expect(try Data(contentsOf: url) == data) }
            #expect(try nonRegular.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
            // Reporting partial results must not weaken full-library export.
            #expect(throws: (any Error).self) { try repository.backupRecords() }
        }
    }

    @Test("An entirely unreadable library is not a successful empty read and recovers on retry")
    func unreadableOnlyAndRetry() throws {
        try withRepository { repository, directory in
            let group = SavedGroup(name: "Preserved identity")
            #expect(repository.save(group))
            let url = directory.appendingPathComponent(group.id.uuidString.lowercased() + ".json")
            let original = try Data(contentsOf: url)
            let corrupt = Data("{".utf8)
            try corrupt.write(to: url)

            let failed = repository.snapshot
            #expect(failed.groups.isEmpty)
            #expect(failed.unreadableCount == 1)
            #expect(failed.hasReadFailures)
            #expect(!failed.directoryFailure)
            #expect(try Data(contentsOf: url) == corrupt)
            #expect(throws: (any Error).self) { try repository.backupRecords() }

            try original.write(to: url)
            let recovered = repository.snapshot
            #expect(recovered.groups == [group])
            #expect(!recovered.hasReadFailures)
            #expect(try repository.backupRecords() == [group])
            #expect(try Data(contentsOf: url) == original)
        }
    }

    private func recordURL(in directory: URL) -> URL {
        directory.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
    }

    private func withRepository(_ body: (SavedGroupRepository, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppFolder-read-report-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(SavedGroupRepository(directory: directory), directory)
    }
}
