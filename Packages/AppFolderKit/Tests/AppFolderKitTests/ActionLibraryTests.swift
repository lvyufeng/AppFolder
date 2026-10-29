import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Action-name library")
struct ActionLibraryTests {
    @Test("Names retain binding identity while tags normalize and have explicit limits")
    func nameAndTagValidation() throws {
        let record = try #require(ActionLibraryRecord(name: "  Cafe\u{301}  ", tags: [" 工作 ", "Work", "work", "Cafe\u{301}"]))
        #expect(record.name.utf8.elementsEqual("Café".utf8))
        #expect(record.id == SavedGroupBinding.normalizedName("CAFE\u{301}"))
        #expect(record.tags == ["Café", "Work", "工作"])
        #expect(record.isValid)
        #expect(ActionLibraryRecord(name: "Manual")?.tags == [])
        #expect(ActionLibraryRecord(name: String(repeating: "x", count: 80)) != nil)
        for invalid in ["", " \u{00A0}", "x\ny", "\tName", String(repeating: "x", count: 81),
                        "x" + String(repeating: "\u{301}", count: 256)] {
            #expect(ActionLibraryRecord(name: invalid) == nil)
        }
        for invalid in ["", "  ", "x\ny", String(repeating: "x", count: 33),
                        "x" + String(repeating: "\u{301}", count: 64)] {
            #expect(ActionLibraryRecord(name: "A", tags: [invalid]) == nil)
        }
        #expect(ActionLibraryRecord(name: "A", tags: (0..<16).map { "Tag \($0)" }) != nil)
        #expect(ActionLibraryRecord(name: "A", tags: (0..<17).map { "Tag \($0)" }) == nil)
        #expect(ActionLibraryRecord(name: "Ａ")?.id != ActionLibraryRecord(name: "A")?.id)
        #expect(ActionLibraryRecord(name: "resume")?.id != ActionLibraryRecord(name: "résumé")?.id)
    }

    @Test("Stored metadata rejects malformed, noncanonical, duplicate and unknown fields")
    func strictRecordDecoding() throws {
        let value = try #require(ActionLibraryRecord(name: "Café", tags: ["工作"], isArchived: true))
        #expect(try JSONDecoder().decode(ActionLibraryRecord.self, from: JSONEncoder().encode(value)) == value)
        let invalid: [String] = [
            #"{"name":"A","tags":["Work","work"],"isArchived":false}"#,
            #"{"name":" A ","tags":[],"isArchived":false}"#,
            #"{"name":"Cafe\u0301","tags":[],"isArchived":false}"#,
            #"{"name":"A","tags":[" Work "],"isArchived":false}"#,
            #"{"name":"A","tags":[],"isArchived":null}"#,
            #"{"name":"A","tags":[]}"#,
            #"{"name":"A","tags":[],"isArchived":false,"target":"tel:123"}"#
        ]
        for json in invalid {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ActionLibraryRecord.self, from: Data(json.utf8)) }
        }
    }

    @Test("Projection unions actual names without catalog guesses or binding aliases")
    func projectedSources() throws {
        let archived = try #require(ActionLibraryRecord(name: "Café", tags: ["工作"], isArchived: true))
        let manual = try #require(ActionLibraryRecord(name: "Hand Typed"))
        var aliased = GroupItem.action(name: "Calendar")
        aliased.displayName = "Café"
        let group = SavedGroup(name: "Group", items: [.folder(name: "Folder", children: [aliased, .action(name: "cafe\u{301}")]),
                                                      .website(name: "Website", url: "https://example.com")])
        let original = group
        let entries = ActionLibraryProjection.entries(records: [archived, manual], savedGroups: [group],
                                                       observedNames: ["CAFE\u{301}", "WeChat"],
                                                       customIconNames: ["café"], mappingNames: ["CAFÉ", "微信"])
        let cafe = try #require(entries.first { $0.id == archived.id })
        #expect(cafe.name == "Café" && cafe.isArchived && cafe.tags == ["工作"])
        #expect(cafe.sources == [.library, .observedWidget, .savedGroup, .customIcon, .manualMapping])
        #expect(entries.first { $0.name == "Calendar" }?.sources == [.savedGroup])
        #expect(entries.first { $0.name == "Hand Typed" }?.sources == [.library])
        #expect(entries.contains { $0.name == "WeChat" } && entries.contains { $0.name == "微信" })
        #expect(!entries.contains { $0.name == "Website" || $0.name == "Folder" })
        #expect(group == original)
        #expect(SavedGroupBinding(actionNames: ["Café", "CAFÉ"]).resolve(cafe.name) == .ambiguous)
        #expect(entries.map(\.id) == entries.map(\.id).sorted())
    }

    @Test("Long observed names remain visible, disabled and byte-for-byte unshortened")
    func preservesUnaddableNames() throws {
        let long = String(repeating: "Long", count: 25)
        let entries = ActionLibraryProjection.entries(records: [], observedNames: [long, "Ａ", "A", "résumé", "resume"])
        #expect(entries.count == 5)
        #expect(entries.first { $0.name == long }?.canAdd == false)
        #expect(entries.filter(\.canAdd).count == 4)
    }

    @Test("First-use reads stay empty without creating data; explicit batch persists across reload")
    func batchPersistence() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(repo.snapshot == .init(status: .available))
        #expect(!FileManager.default.fileExists(atPath: try #require(repo.directory).path))
        let a = try #require(ActionLibraryRecord(name: "Manual", tags: ["Work"]))
        let b = try #require(ActionLibraryRecord(name: "Café", isArchived: true))
        let saved = try repo.apply([.init(name: a.name, expected: nil, replacement: a), .init(name: b.name, expected: nil, replacement: b)])
        #expect(saved.records == [b, a])
        #expect(ActionLibraryRepository(directory: repo.directory).snapshot == saved)
        #expect(try repo.exportRecords(for: [b.id]) == [b])
        #expect(try repo.exportRecords(for: []) == [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["ActionLibrary"])
    }

    @Test("One stale expected row rejects an entire batch; unrelated fresh edits are preserved")
    func batchCompareAndSet() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(ActionLibraryRecord(name: "A"))
        let b = try #require(ActionLibraryRecord(name: "B"))
        #expect(repo.insertMissing([a, b]).didCommit)
        let editedA = try #require(ActionLibraryRecord(name: "A", tags: ["Elsewhere"]))
        _ = try repo.apply([.init(name: a.name, expected: a, replacement: editedA)])
        let before = try Data(contentsOf: recordURL(repo))
        let archivedB = try #require(ActionLibraryRecord(name: "B", isArchived: true))
        #expect(throws: ActionLibraryError.conflict([a.id])) {
            try repo.apply([.init(name: a.name, expected: a, replacement: nil),
                            .init(name: b.name, expected: b, replacement: archivedB)])
        }
        #expect(try Data(contentsOf: recordURL(repo)) == before)
        _ = try repo.apply([.init(name: b.name, expected: b, replacement: archivedB)])
        #expect(repo.snapshot.records == [editedA, archivedB])
        #expect(throws: ActionLibraryError.invalidChanges) {
            try repo.apply([.init(name: "A", expected: editedA, replacement: nil),
                            .init(name: " a ", expected: editedA, replacement: nil)])
        }
    }

    @Test("Archive survives refreshed evidence and deleting metadata does not mutate saved layouts")
    func archiveAndUnarchive() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = SavedGroup(name: "Saved", items: [.action(name: "Calendar")])
        let archived = try #require(ActionLibraryRecord(name: "Calendar", isArchived: true))
        _ = try repo.apply([.init(name: archived.name, expected: nil, replacement: archived)])
        let rows = ActionLibraryProjection.entries(records: repo.snapshot.records, savedGroups: [group], observedNames: ["CALENDAR"])
        #expect(rows.count == 1 && rows[0].isArchived)
        #expect(group.allActionNames == ["Calendar"])
        _ = try repo.apply([.init(name: archived.name, expected: archived, replacement: nil)])
        let restored = ActionLibraryProjection.entries(records: repo.snapshot.records, savedGroups: [group])
        #expect(restored.count == 1 && !restored[0].isArchived && restored[0].record == nil)
        #expect(group.items.count == 1)
    }

    @Test("Corrupt libraries are unavailable for mutation and never overwritten as empty")
    func corruptionIsNotEmpty() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: try #require(repo.directory), withIntermediateDirectories: true)
        let a = try #require(ActionLibraryRecord(name: "A"))
        let corrupt: [Data] = [Data(), Data("broken".utf8), Data(#"{"version":2,"records":[]}"#.utf8),
                              Data(#"{"version":1,"records":[{"name":"A","tags":[],"isArchived":false},{"name":"a","tags":[],"isArchived":true}]}"#.utf8),
                              Data(repeating: 0, count: ActionLibraryRepository.maximumFileBytes + 1)]
        for bytes in corrupt {
            try bytes.write(to: recordURL(repo), options: .atomic)
            #expect(repo.snapshot.status == .unreadable)
            #expect(throws: ActionLibraryError.unreadable) { try repo.exportRecords() }
            #expect(throws: ActionLibraryError.unreadable) { try repo.apply([.init(name: a.name, expected: nil, replacement: a)]) }
            let receipt = repo.insertMissing([a])
            #expect(!receipt.didCommit && receipt.attemptedRecords.isEmpty && receipt.error == .unreadable)
            #expect(throws: ActionLibraryError.unreadable) { try repo.rollbackMatching([a]) }
            #expect(try Data(contentsOf: recordURL(repo)) == bytes)
            #expect(try repo.exportRecords(for: []) == [])
        }
    }

    @Test("A competing file lock and nonregular paths cannot be mistaken for a new library")
    func locksAndPathBoundaries() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(ActionLibraryRecord(name: "A"))
        #expect(ActionLibraryRepository(directory: nil).snapshot.status == .unavailable)
        #expect(!ActionLibraryRepository(directory: nil).insertMissing([a]).didCommit)
        #expect(repo.insertMissing([a]).didCommit)
        let directory = try #require(repo.directory)
        let lock = open(directory.appendingPathComponent(".lock").path, O_RDWR)
        #expect(lock >= 0)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        #expect(repo.snapshot.status == .busy)
        let b = try #require(ActionLibraryRecord(name: "B"))
        let busy = repo.insertMissing([b])
        #expect(busy.error == .busy && busy.attemptedRecords.isEmpty)
        #expect(flock(lock, LOCK_UN) == 0)
        #expect(repo.snapshot.records == [a])
        let external = root.appendingPathComponent("external.json")
        let original = try Data(contentsOf: recordURL(repo))
        try original.write(to: external)
        try FileManager.default.removeItem(at: recordURL(repo))
        try FileManager.default.createSymbolicLink(at: recordURL(repo), withDestinationURL: external)
        #expect(repo.snapshot.status == .unreadable)
        #expect(!repo.insertMissing([a]).didCommit)
        #expect(try Data(contentsOf: external) == original)
        let directoryLink = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: directory)
        #expect(ActionLibraryRepository(directory: directoryLink).snapshot.status == .unreadable)
        let fileAsDirectory = ActionLibraryRepository(directory: external)
        #expect(fileAsDirectory.snapshot.status == .unreadable)
        let invalidPath = root.appendingPathComponent("invalid\u{0000}path", isDirectory: true)
        #expect(ActionLibraryRepository(directory: invalidPath).snapshot.status == .unreadable)
        try FileManager.default.removeItem(at: directory.appendingPathComponent(".lock"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(".lock"), withDestinationURL: external)
        #expect(repo.snapshot.status == .unreadable)
        #expect(try Data(contentsOf: external) == original)
    }

    @Test("Import checks fresh state and its receipt never claims an existing equal record")
    func receiptOwnsOnlyNewRows() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try #require(ActionLibraryRecord(name: "A", tags: ["Local"]))
        let incomingA = try #require(ActionLibraryRecord(name: "A", tags: ["Imported"], isArchived: true))
        let b = try #require(ActionLibraryRecord(name: "B"))
        let c = try #require(ActionLibraryRecord(name: "C"))
        #expect(repo.insertMissing([a, b]).didCommit)
        let receipt = repo.insertMissing([incomingA, b, c])
        #expect(receipt.didCommit && receipt.attemptedRecords == [c])
        #expect(receipt.keptExistingRecords == [a, b])
        #expect(try repo.rollbackMatching(receipt.attemptedRecords).remainingNames.isEmpty)
        #expect(repo.snapshot.records == [a, b])
    }

    @Test("Rollback preserves later user edits and removes the rest in one file replacement")
    func rollbackPreservesLaterEdits() throws {
        let (base, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let io = CountingWriter()
        let repo = ActionLibraryRepository(directory: base.directory, writeData: io.write)
        let a = try #require(ActionLibraryRecord(name: "A"))
        let b = try #require(ActionLibraryRecord(name: "B"))
        let receipt = repo.insertMissing([a, b])
        let changed = try #require(ActionLibraryRecord(name: "A", tags: ["Keep"], isArchived: true))
        _ = try repo.apply([.init(name: a.name, expected: a, replacement: changed)])
        let writesBefore = io.count
        let result = try repo.rollbackMatching(receipt.attemptedRecords)
        #expect(result.remainingNames == [a.id])
        #expect(repo.snapshot.records == [changed])
        #expect(io.count == writesBefore + 1)
    }

    @Test("Write errors retain ownership; confirmed post-rename bytes count as success")
    func writeFailureReceipts() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = try #require(ActionLibraryRecord(name: "Existing"))
        let added = try #require(ActionLibraryRecord(name: "Added"))
        #expect(repo.insertMissing([existing]).didCommit)
        let before = try Data(contentsOf: recordURL(repo))
        let failure = ActionLibraryRepository(directory: repo.directory) { _, _ in throw TestFailure.injected }
        let failed = failure.insertMissing([existing, added])
        #expect(!failed.didCommit && failed.attemptedRecords == [added] && failed.keptExistingRecords == [existing])
        #expect(try Data(contentsOf: recordURL(repo)) == before)
        #expect(try repo.rollbackMatching(failed.attemptedRecords).remainingNames.isEmpty)
        #expect(repo.snapshot.records == [existing])
        let errorAfterRename = ActionLibraryRepository(directory: repo.directory) { data, url in
            try data.write(to: url, options: .atomic)
            throw TestFailure.injected
        }
        let committed = errorAfterRename.insertMissing([existing, added])
        #expect(committed.didCommit && committed.error == nil && committed.attemptedRecords == [added])
        #expect(repo.snapshot.records == [added, existing])
    }

    @Test("Unknown post-write bytes cannot lose the importer ledger or erase damaged data")
    func uncertainWriteRetainsReceipt() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = try #require(ActionLibraryRecord(name: "Existing"))
        let added = try #require(ActionLibraryRecord(name: "Added"))
        #expect(repo.insertMissing([existing]).didCommit)
        let unconfirmed = ActionLibraryRepository(directory: repo.directory) { _, url in
            try Data("injected broken replacement".utf8).write(to: url, options: .atomic)
            throw TestFailure.injected
        }
        let receipt = unconfirmed.insertMissing([existing, added])
        #expect(!receipt.didCommit && receipt.attemptedRecords == [added] && receipt.keptExistingRecords == [existing])
        #expect(throws: ActionLibraryError.unreadable) { try repo.rollbackMatching(receipt.attemptedRecords) }
        #expect(try Data(contentsOf: recordURL(repo)) == Data("injected broken replacement".utf8))
    }

    @Test("Large inserts and bulk edits replace the file once, no-ops never rewrite, overflow is all-or-nothing")
    func boundedBatchAndNoop() throws {
        let (base, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let io = CountingWriter()
        let repo = ActionLibraryRepository(directory: base.directory, writeData: io.write)
        let records = (0..<ActionLibraryRepository.maximumRecords).compactMap { ActionLibraryRecord(name: "Name \($0)") }
        #expect(repo.insertMissing(records).didCommit && io.count == 1)
        #expect(repo.insertMissing(records).attemptedRecords.isEmpty && io.count == 1)
        let first = try #require(records.first)
        _ = try repo.apply([.init(name: first.name, expected: first, replacement: first)])
        #expect(io.count == 1)
        let extra = try #require(ActionLibraryRecord(name: "One too many"))
        let before = try Data(contentsOf: recordURL(repo))
        let overflow = repo.insertMissing([extra])
        #expect(!overflow.didCommit && overflow.attemptedRecords.isEmpty && overflow.error == .capacityExceeded)
        #expect(try Data(contentsOf: recordURL(repo)) == before && io.count == 1)
        let mutations = records.map { record in
            ActionLibraryMutation(name: record.name, expected: record,
                                  replacement: ActionLibraryRecord(name: record.name, tags: ["Work"], isArchived: true))
        }
        let updated = try repo.apply(mutations)
        #expect(updated.records.count == records.count && updated.records.allSatisfy(\.isArchived))
        #expect(io.count == 2)
        let replacements = (0..<ActionLibraryRepository.maximumRecords).compactMap {
            ActionLibraryRecord(name: "Replacement \($0)")
        }
        let replaceAll = updated.records.map { ActionLibraryMutation(name: $0.name, expected: $0, replacement: nil) }
            + replacements.map { ActionLibraryMutation(name: $0.name, expected: nil, replacement: $0) }
        #expect(replaceAll.count == 2 * ActionLibraryRepository.maximumRecords)
        let replaced = try repo.apply(replaceAll)
        #expect(replaced.records == replacements.sorted { $0.id < $1.id })
        #expect(io.count == 3)
    }

    @Test("The byte cap rejects a valid-row batch before writing or claiming ownership")
    func totalByteLimit() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let tags = (0..<16).map { String(repeating: "😀", count: 31) + String(UnicodeScalar(0x4E00 + $0)!) }
        let records = (0..<ActionLibraryRepository.maximumRecords).compactMap {
            ActionLibraryRecord(name: "Name \($0)", tags: tags)
        }
        #expect(records.count == ActionLibraryRepository.maximumRecords)
        let result = repo.insertMissing(records)
        #expect(!result.didCommit && result.error == .capacityExceeded && result.attemptedRecords.isEmpty)
        #expect(repo.snapshot.records.isEmpty && repo.snapshot.status == .available)
        #expect(!FileManager.default.fileExists(atPath: try recordURL(repo).path))
    }

    private func repository() throws -> (ActionLibraryRepository, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("action-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (.init(directory: root.appendingPathComponent("ActionLibrary", isDirectory: true)), root)
    }

    private func recordURL(_ repository: ActionLibraryRepository) throws -> URL {
        try #require(repository.directory).appendingPathComponent("library.json")
    }
}

private enum TestFailure: Error { case injected }

private final class CountingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    var count: Int { lock.withLock { writes } }
    func write(_ data: Data, to url: URL) throws {
        lock.withLock { writes += 1 }
        try data.write(to: url, options: .atomic)
    }
}
