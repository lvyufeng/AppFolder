import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Appearance preset repository")
struct AppearancePresetStoreTests {
    @Test("First reads and missing-file rollbacks create no directory, document or lock")
    func firstUseAndPersistence() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(repo.directory)
        let a = record("A")
        #expect(repo.isAvailable && repo.snapshot == .init(status: .available))
        #expect(try repo.exportRecords().isEmpty)
        #expect(try repo.rollbackMatching([a]).remainingNames.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(repo.snapshot == .init(status: .available))
        #expect(try repo.rollbackMatching([a]).remainingNames.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let b = record("B", tint: "#ABCDE1")
        let saved = try repo.apply([.init(name: b.name, expected: nil, replacement: b),
                                    .init(name: a.name, expected: nil, replacement: a)])
        #expect(saved.records == [a, b])
        #expect(AppearancePresetRepository(directory: directory).snapshot == saved)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == [".lock", "library.json"])
    }

    @Test("CAS conflicts leave the complete batch untouched and rename checks both identities")
    func atomicRenameAndCAS() throws {
        let (base, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = PresetCountingWriter()
        let repo = AppearancePresetRepository(directory: base.directory, writeData: writer.write)
        let a = record("A"), b = record("B"), c = record("C")
        #expect(repo.insertMissing([a, b]).didCommit)
        let updatedA = record("A", tint: "#123456")
        _ = try repo.apply([.init(name: a.name, expected: a, replacement: updatedA)])
        let before = try Data(contentsOf: recordURL(repo))
        #expect(throws: AppearancePresetError.conflict([a.id])) {
            try repo.apply([.init(name: a.name, expected: a, replacement: nil),
                            .init(name: b.name, expected: b, replacement: nil),
                            .init(name: c.name, expected: nil, replacement: c)])
        }
        #expect(try Data(contentsOf: recordURL(repo)) == before && writer.count == 2)
        #expect(throws: AppearancePresetError.conflict([b.id])) {
            try repo.apply([.init(name: a.name, expected: updatedA, replacement: nil),
                            .init(name: b.name, expected: nil, replacement: b)])
        }
        let renamed = AppearancePreset(name: c.name, appearance: updatedA.appearance)
        #expect(try repo.apply([.init(name: a.name, expected: updatedA, replacement: nil),
                                .init(name: c.name, expected: nil, replacement: renamed)]).records == [b, renamed])
        #expect(writer.count == 3)
        let displayCase = AppearancePreset(name: "c", appearance: renamed.appearance)
        _ = try repo.apply([.init(name: " C ", expected: renamed, replacement: displayCase)])
        #expect(repo.snapshot.records == [b, displayCase] && writer.count == 4)
    }

    @Test("Concurrent editors with the same expected record have exactly one winner")
    func competingWriters() async throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = record("Shared")
        #expect(repo.insertMissing([original]).didCommit)
        let winners = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let replacement = AppearancePreset(name: original.name,
                                                       appearance: .init(tintHex: String(format: "#%06X", index + 1)))
                    do {
                        _ = try repo.apply([.init(name: original.name, expected: original, replacement: replacement)])
                        return true
                    } catch {
                        #expect(error as? AppearancePresetError == .conflict([original.id]))
                        return false
                    }
                }
            }
            var count = 0
            for await won in group { if won { count += 1 } }
            return count
        }
        #expect(winners == 1 && repo.snapshot.records.count == 1 && repo.snapshot.records != [original])
    }

    @Test("Every appearance field and display spelling participates in CAS")
    func appearanceCAS() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = record("Look")
        #expect(repo.insertMissing([baseline]).didCommit)
        var variants: [SavedGroupAppearance] = []
        var grid = baseline.appearance; grid.grid = .four; variants.append(grid)
        var titles = baseline.appearance; titles.showsTitles.toggle(); variants.append(titles)
        var size = baseline.appearance; size.iconSize = .large; variants.append(size)
        var plate = baseline.appearance; plate.plate = .gradient; variants.append(plate)
        var tint = baseline.appearance; tint.tintHex = "#123456"; variants.append(tint)
        var density = baseline.appearance; density.density = .dense; variants.append(density)
        var back = baseline.appearance; back.backButtonStyle = .folder; variants.append(back)
        let changed = variants.map { AppearancePreset(name: baseline.name, appearance: $0) }
            + [AppearancePreset(name: "LOOK", appearance: baseline.appearance)]
        for replacement in changed {
            _ = try repo.apply([.init(name: baseline.name, expected: baseline, replacement: replacement)])
            #expect(throws: AppearancePresetError.conflict([baseline.id])) {
                try repo.apply([.init(name: baseline.name, expected: baseline, replacement: nil)])
            }
            _ = try repo.apply([.init(name: baseline.name, expected: replacement, replacement: baseline)])
        }
    }

    @Test("Invalid mutations reject before touching disk and cannot disguise a rename")
    func mutationValidation() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = record("A"), b = record("B")
        let bad = AppearancePreset(name: "Bad", appearance: .init(tintHex: "bad"))
        let batches: [[AppearancePresetMutation]] = [
            [.init(name: "A", expected: nil, replacement: b)],
            [.init(name: "A", expected: b, replacement: nil)],
            [.init(name: "A", expected: nil, replacement: a), .init(name: " a ", expected: nil, replacement: a)],
            [.init(name: "\tA", expected: nil, replacement: a)],
            [.init(name: "Bad", expected: nil, replacement: bad)]
        ]
        for batch in batches {
            #expect(throws: AppearancePresetError.invalidChanges) { try repo.apply(batch) }
        }
        #expect(repo.insertMissing([a, AppearancePreset(name: "a", appearance: .default)]).error == .invalidChanges)
        #expect(repo.insertMissing([bad]).error == .invalidChanges)
        #expect(!FileManager.default.fileExists(atPath: try #require(repo.directory).path))
    }

    @Test("Record capacity is atomic, supports full replacement and no-ops never rewrite")
    func capacityAndNoOp() throws {
        let (base, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = PresetCountingWriter()
        let repo = AppearancePresetRepository(directory: base.directory, writeData: writer.write)
        let records = (0..<64).map { record("Name \($0)") }
        #expect(repo.insertMissing(records).didCommit && writer.count == 1)
        #expect(repo.insertMissing(records).attemptedRecords.isEmpty && writer.count == 1)
        let first = records[0]
        _ = try repo.apply([.init(name: first.name, expected: first, replacement: first)])
        _ = try repo.apply([])
        #expect(writer.count == 1)
        let extra = record("Extra")
        let receipt = repo.insertMissing([first, extra])
        #expect(!receipt.didCommit && receipt.error == .capacityExceeded && receipt.attemptedRecords.isEmpty)
        #expect(receipt.keptExistingRecords == [first] && writer.count == 1)
        #expect(throws: AppearancePresetError.capacityExceeded) {
            try repo.apply([.init(name: extra.name, expected: nil, replacement: extra)])
        }
        let replacements = (0..<64).map { record("Replacement \($0)", tint: "#010203") }
        let mutations = records.map { AppearancePresetMutation(name: $0.name, expected: $0, replacement: nil) }
            + replacements.map { AppearancePresetMutation(name: $0.name, expected: nil, replacement: $0) }
        #expect(try repo.apply(mutations).records == replacements.sorted { $0.id < $1.id })
        #expect(writer.count == 2)
    }

    @Test("The largest legal names fit and an exact byte cap reads while one extra byte is protected")
    func byteBoundaries() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = (0..<64).map { index in
            record(String(repeating: "😀", count: 63) + String(UnicodeScalar(0x1F300 + index)!))
        }
        #expect(records.allSatisfy { $0.name.utf8.count == 256 && $0.isValid })
        #expect(repo.insertMissing(records).didCommit)
        let url = try recordURL(repo)
        var data = try Data(contentsOf: url)
        #expect(data.count < AppearancePresetRepository.maximumFileBytes)
        data.append(Data(repeating: 0x20, count: AppearancePresetRepository.maximumFileBytes - data.count))
        try data.write(to: url, options: .atomic)
        #expect(try repo.exportRecords().count == 64)
        data.append(0x20)
        try data.write(to: url, options: .atomic)
        #expect(repo.snapshot.status == .unreadable)
        #expect(throws: AppearancePresetError.unreadable) {
            try repo.apply([.init(name: records[0].name, expected: records[0], replacement: nil)])
        }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("Corrupt, unknown and duplicate documents stay unreadable and are never overwritten")
    func corruptionProtection() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: try #require(repo.directory), withIntermediateDirectories: true)
        let a = record("A")
        let row = try #require(String(data: JSONEncoder().encode(a), encoding: .utf8))
        let tooMany = Array(repeating: row, count: 65).joined(separator: ",")
        let corrupt = [Data(), Data("broken".utf8), Data(#"{"version":2,"records":[]}"#.utf8),
                       Data(#"{"version":1,"records":[],"unknown":true}"#.utf8),
                       Data(#"{"version":1,"records":null}"#.utf8),
                       Data("{\"version\":1,\"records\":[\(row),\(row)]}".utf8),
                       Data("{\"version\":1,\"records\":[\(tooMany)]}".utf8)]
        for bytes in corrupt {
            try bytes.write(to: recordURL(repo), options: .atomic)
            #expect(repo.snapshot.status == .unreadable)
            #expect(throws: AppearancePresetError.unreadable) { try repo.exportRecords() }
            #expect(throws: AppearancePresetError.unreadable) { try repo.apply([.init(name: a.name, expected: nil, replacement: a)]) }
            let receipt = repo.insertMissing([a])
            #expect(!receipt.didCommit && receipt.attemptedRecords.isEmpty && receipt.error == .unreadable)
            #expect(throws: AppearancePresetError.unreadable) { try repo.rollbackMatching([a]) }
            #expect(try Data(contentsOf: recordURL(repo)) == bytes)
        }
    }

    @Test("Unavailable storage, file locks, symbolic links and nonregular paths cannot appear empty")
    func pathAndLockProtection() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = record("A")
        #expect(AppearancePresetRepository(directory: nil).snapshot.status == .unavailable)
        #expect(AppearancePresetRepository(directory: nil).insertMissing([a]).error == .unavailable)
        #expect(repo.insertMissing([a]).didCommit)
        let directory = try #require(repo.directory)
        let lockURL = directory.appendingPathComponent(".lock")
        let lock = open(lockURL.path, O_RDWR)
        #expect(lock >= 0)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        #expect(repo.snapshot.status == .busy)
        #expect(repo.insertMissing([record("B")]).error == .busy)
        #expect(throws: AppearancePresetError.busy) { try repo.apply([.init(name: a.name, expected: a, replacement: nil)]) }
        #expect(flock(lock, LOCK_UN) == 0)
        let external = root.appendingPathComponent("external.json")
        let original = try Data(contentsOf: recordURL(repo))
        try original.write(to: external)
        try FileManager.default.removeItem(at: recordURL(repo))
        try FileManager.default.createSymbolicLink(at: recordURL(repo), withDestinationURL: external)
        #expect(repo.snapshot.status == .unreadable)
        #expect(repo.insertMissing([record("B")]).error == .unreadable)
        #expect(try Data(contentsOf: external) == original)
        let linkedDirectory = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: directory)
        #expect(AppearancePresetRepository(directory: linkedDirectory).snapshot.status == .unreadable)
        #expect(AppearancePresetRepository(directory: external).snapshot.status == .unreadable)
        #expect(AppearancePresetRepository(directory: URL(string: "https://example.org/")).snapshot.status == .unreadable)
        // Foundation can collapse a NUL-containing component to file:// or
        // file:/// before the repository sees it. Neither is a valid store.
        for isDirectory in [false, true] {
            let invalid = root.appendingPathComponent("invalid\u{0000}path", isDirectory: isDirectory)
            #expect(AppearancePresetRepository(directory: invalid).snapshot.status == .unreadable)
        }
        try FileManager.default.removeItem(at: recordURL(repo))
        #expect(mkfifo(try recordURL(repo).path, S_IRUSR | S_IWUSR) == 0)
        #expect(repo.snapshot.status == .unreadable)
        #expect(repo.insertMissing([a]).error == .unreadable)
        try FileManager.default.removeItem(at: recordURL(repo))
        try original.write(to: recordURL(repo), options: .atomic)
        try FileManager.default.removeItem(at: lockURL)
        try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: external)
        #expect(repo.snapshot.status == .unreadable)
        #expect(repo.insertMissing([a]).error == .unreadable)
        #expect(try Data(contentsOf: external) == original)
    }

    @Test("Import receipts own only new locked rows and rollback preserves subsequent user changes")
    func ownershipAndRollback() throws {
        let (base, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = PresetCountingWriter()
        let repo = AppearancePresetRepository(directory: base.directory, writeData: writer.write)
        let a = record("A"), b = record("B"), c = record("C"), d = record("D")
        #expect(repo.insertMissing([a, b]).didCommit)
        let receipt = repo.insertMissing([record("a", tint: "#999999"), b, c, d])
        #expect(receipt.didCommit && receipt.attemptedRecords == [c, d] && receipt.keptExistingRecords == [a, b])
        let changedC = record("C", tint: "#123456")
        _ = try repo.apply([.init(name: c.name, expected: c, replacement: changedC)])
        let before = writer.count
        #expect(try repo.rollbackMatching(receipt.attemptedRecords).remainingNames == [c.id])
        #expect(repo.snapshot.records == [a, b, changedC] && writer.count == before + 1)
        #expect(try repo.rollbackMatching(receipt.attemptedRecords).remainingNames == [c.id])
        #expect(writer.count == before + 1)
    }

    @Test("Write failures preserve ownership and exact readback accepts errors after atomic replacement")
    func readbackAndFailureReceipts() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = record("Existing"), added = record("Added")
        #expect(repo.insertMissing([existing]).didCommit)
        let failure = AppearancePresetRepository(directory: repo.directory) { _, _ in throw PresetTestFailure.injected }
        let receipt = failure.insertMissing([existing, added])
        #expect(!receipt.didCommit && receipt.error == .writeFailed)
        #expect(receipt.attemptedRecords == [added] && receipt.keptExistingRecords == [existing])
        #expect(repo.snapshot.records == [existing])
        #expect(try repo.rollbackMatching(receipt.attemptedRecords).remainingNames.isEmpty)
        let afterRename = AppearancePresetRepository(directory: repo.directory) { data, url in
            try data.write(to: url, options: .atomic)
            throw PresetTestFailure.injected
        }
        #expect(afterRename.insertMissing([added]).didCommit)
        #expect(try failure.rollbackMatching([added]).remainingNames == [added.id])
        #expect(try afterRename.rollbackMatching([added]).remainingNames.isEmpty)
        #expect(repo.snapshot.records == [existing])
        #expect(throws: AppearancePresetError.writeFailed) {
            try failure.apply([.init(name: existing.name, expected: existing, replacement: nil)])
        }
        #expect(repo.snapshot.records == [existing])
    }

    @Test("Unknown bytes after an attempted write retain the ledger and cannot be erased by rollback")
    func unconfirmedWrite() throws {
        let (repo, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = record("Existing"), added = record("Added")
        #expect(repo.insertMissing([existing]).didCommit)
        let damaged = Data("injected incomplete replacement".utf8)
        let uncertain = AppearancePresetRepository(directory: repo.directory) { _, url in
            try damaged.write(to: url, options: .atomic)
            throw PresetTestFailure.injected
        }
        let receipt = uncertain.insertMissing([existing, added])
        #expect(!receipt.didCommit && receipt.attemptedRecords == [added] && receipt.keptExistingRecords == [existing])
        #expect(throws: AppearancePresetError.unreadable) { try repo.rollbackMatching(receipt.attemptedRecords) }
        #expect(try Data(contentsOf: recordURL(repo)) == damaged)
    }

    private func record(_ name: String, tint: String = "#0A84FF") -> AppearancePreset {
        .init(name: name, appearance: .init(tintHex: tint))
    }

    private func repository() throws -> (AppearancePresetRepository, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("appearance-presets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (.init(directory: root.appendingPathComponent("AppearancePresets", isDirectory: true)), root)
    }

    private func recordURL(_ repository: AppearancePresetRepository) throws -> URL {
        try #require(repository.directory).appendingPathComponent("library.json")
    }
}

private enum PresetTestFailure: Error { case injected }

private final class PresetCountingWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    var count: Int { lock.withLock { writes } }
    func write(_ data: Data, to url: URL) throws {
        lock.withLock { writes += 1 }
        try data.write(to: url, options: .atomic)
    }
}
