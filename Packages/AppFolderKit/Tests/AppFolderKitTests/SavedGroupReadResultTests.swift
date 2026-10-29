import Darwin
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Individual saved group read results")
struct SavedGroupReadResultTests {
    @Test("Unavailable and genuinely missing storage have separate results without creating files")
    func unavailableAndMissing() throws {
        let id = UUID()
        let unavailable = SavedGroupRepository(directory: nil)
        #expect(unavailable.readResult(id: id) == .unavailable)
        #expect(unavailable.group(id: id) == nil)
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(store.readResult(id: id) == .missing)
        #expect(!FileManager.default.fileExists(atPath: try #require(store.directory).path))
        try FileManager.default.createDirectory(at: try #require(store.directory), withIntermediateDirectories: false)
        #expect(store.readResult(id: id) == .missing)
    }

    @Test("An unrelated broken JSON cannot make a missing target appear unreadable")
    func missingTargetIgnoresOtherDamage() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let readable = SavedGroup(name: "Readable", items: [.action(name: "Maps")])
        #expect(store.save(readable))
        let broken = file(UUID(), store)
        let bytes = Data("bad unrelated JSON".utf8)
        try bytes.write(to: broken)
        #expect(store.snapshot.unreadableCount == 1)
        #expect(store.readResult(id: UUID()) == .missing)
        #expect(store.readResult(id: readable.id) == .loaded(readable))
        #expect(try Data(contentsOf: broken) == bytes)
        #expect(store.remove(id: readable.id))
        #expect(store.readResult(id: readable.id) == .missing)
    }

    @Test("A damaged target is unreadable even when all other groups load")
    func targetDamageIsIndependent() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = SavedGroup(name: "Still readable")
        #expect(store.save(good))
        let id = UUID()
        let invalid = Data("{truncated".utf8)
        try invalid.write(to: file(id, store))
        #expect(store.readResult(id: id) == .unreadable)
        #expect(store.group(id: id) == nil)
        #expect(store.group(id: good.id) == good)
        #expect(try Data(contentsOf: file(id, store)) == invalid)
    }

    @Test("Empty, oversized, invalid and wrong-identity target files are not missing")
    func rejectsInvalidRecords() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: try #require(store.directory), withIntermediateDirectories: false)
        let id = UUID()
        var invalid = SavedGroup(id: id, name: "Initial")
        invalid.name = ""
        let records = [Data(), Data(repeating: 0, count: SavedGroupRepository.maximumFileBytes + 1),
                       try JSONEncoder().encode(invalid), try JSONEncoder().encode(SavedGroup(name: "Different ID"))]
        for bytes in records {
            try bytes.write(to: file(id, store))
            #expect(store.readResult(id: id) == .unreadable)
            #expect(try Data(contentsOf: file(id, store)) == bytes)
        }
    }

    @Test("Directories, FIFOs and symlinks at the record path never load another target")
    func nonregularTargets() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = SavedGroup(name: "Original")
        #expect(store.save(good))
        let directoryID = UUID(), fifoID = UUID(), linkID = UUID(), brokenLinkID = UUID()
        try FileManager.default.createDirectory(at: file(directoryID, store), withIntermediateDirectories: false)
        #expect(mkfifo(file(fifoID, store).path, S_IRUSR | S_IWUSR) == 0)
        try FileManager.default.createSymbolicLink(at: file(linkID, store), withDestinationURL: file(good.id, store))
        try FileManager.default.createSymbolicLink(at: file(brokenLinkID, store), withDestinationURL: root.appendingPathComponent("absent"))
        for id in [directoryID, fifoID, linkID, brokenLinkID] {
            #expect(store.readResult(id: id) == .unreadable)
        }
        #expect(store.readResult(id: good.id) == .loaded(good))
    }

    @Test("Invalid directory paths are unreadable rather than not found")
    func invalidDirectoryPaths() throws {
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try #require(store.directory)
        let bytes = Data("a file cannot contain group files".utf8)
        try bytes.write(to: directory)
        #expect(store.readResult(id: UUID()) == .unreadable)
        #expect(try Data(contentsOf: directory) == bytes)
        let loop = root.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)
        #expect(SavedGroupRepository(directory: loop).readResult(id: UUID()) == .unreadable)
        let nonFile = URL(string: "https://example.com/SavedGroups")!
        #expect(SavedGroupRepository(directory: nonFile).readResult(id: UUID()) == .unreadable)
        let nul = URL(fileURLWithPath: root.path + "/name\u{0000}suffix")
        #expect(SavedGroupRepository(directory: nul).readResult(id: UUID()) == .unreadable)
        // A literal percent sequence is a legal filename, encoded as %2500 in
        // the URL. Rejecting NUL must not recursively decode and reject it too.
        let literal = SavedGroupRepository(directory: root.appendingPathComponent("literal%00"))
        let valid = SavedGroup(name: "Literal percent path")
        #expect(literal.save(valid))
        #expect(literal.readResult(id: valid.id) == .loaded(valid))
    }

    @Test("Permission failures on the target or containing directory are never reported as missing")
    func permissionFailures() throws {
        // Root deliberately bypasses UNIX permissions. Normal developer/test
        // users exercise both EACCES paths below.
        guard geteuid() != 0 else { return }
        let (store, root) = try repository()
        defer { try? FileManager.default.removeItem(at: root) }
        let group = SavedGroup(name: "Private")
        #expect(store.save(group))
        let target = file(group.id, store)
        #expect(chmod(target.path, 0) == 0)
        defer { chmod(target.path, S_IRUSR | S_IWUSR) }
        #expect(store.readResult(id: group.id) == .unreadable)
        #expect(chmod(target.path, S_IRUSR | S_IWUSR) == 0)
        let directory = try #require(store.directory)
        #expect(chmod(directory.path, 0) == 0)
        defer { chmod(directory.path, S_IRWXU) }
        #expect(store.readResult(id: group.id) == .unreadable)
        #expect(store.readResult(id: UUID()) == .unreadable)
        #expect(chmod(directory.path, S_IRWXU) == 0)
        #expect(store.readResult(id: group.id) == .loaded(group))
    }

    private func repository() throws -> (SavedGroupRepository, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("group-read-result-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SavedGroupRepository(directory: root.appendingPathComponent("SavedGroups", isDirectory: true)), root)
    }

    private func file(_ id: UUID, _ store: SavedGroupRepository) -> URL {
        store.directory!.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }
}
