import CryptoKit
import Foundation
import Testing
@testable import AppFolderKit

@Suite("Canonical action artwork storage")
struct CustomIconUnicodeStorageTests {
    private let nfc = "Café Å"
    private let nfd = "Cafe\u{301} A\u{30A}"
    private let mixed = "Café A\u{30A}"

    @Test("New writes use one canonical path and either spelling reads, replaces and clears it", arguments: [false, true])
    func canonicalWrites(decomposed: Bool) throws {
        try withDirectory { root in
            let repo = CustomIconRepository(directory: root)
            let first = try datePair()
            let calendar = try #require(CustomIcon.symbol("calendar"))
            let second = CustomIconVariants(standard: calendar)
            let written = decomposed ? nfd : nfc
            let read = decomposed ? nfc : nfd
            #expect(repo.setVariants(first, name: written))
            #expect(repo.variants(name: read) == first)
            #expect(try filenames(root) == [legacyURL(nfc, in: root).lastPathComponent])
            #expect(repo.setVariants(second, name: read))
            #expect(CustomIconRepository(directory: root).variants(name: written) == second)
            #expect(repo.setVariants(nil, name: written))
            #expect(!repo.containsRecord(name: read))
            #expect(try filenames(root).isEmpty)
        }
    }

    @Test("Mixed legacy spellings are found without mutating bytes and migrate on a successful edit")
    func legacyDiscovery() throws {
        try withDirectory { root in
            let pair = try datePair()
            let old = try legacyRecord(mixed, pair, in: root)
            let bytes = try Data(contentsOf: old)
            let repo = CustomIconRepository(directory: root)
            #expect(repo.variants(name: nfc) == pair)
            #expect(repo.variants(name: nfd) == pair)
            #expect(repo.all[SavedGroupBinding.normalizedName(nfc)] == pair)
            #expect(try repo.backupIcon(name: nfc) == pair)
            #expect(try Data(contentsOf: old) == bytes)
            #expect(try filenames(root).count == 1)
            #expect(repo.setVariants(pair, name: nfd))
            #expect(!FileManager.default.fileExists(atPath: old.path))
            #expect(try filenames(root) == [legacyURL(nfc, in: root).lastPathComponent])
            #expect(CustomIconRepository(directory: root).variants(name: mixed) == pair)
        }
    }

    @Test("Identical legacy aliases export once; different content fails closed until explicit clear")
    func aliasesAndConflicts() throws {
        try withDirectory { root in
            let pair = try datePair()
            let first = try legacyRecord(nfd, pair, in: root)
            let second = try legacyRecord(mixed, pair, in: root)
            let repo = CustomIconRepository(directory: root)
            #expect(repo.variants(name: nfc) == pair)
            #expect(try repo.backupRecords().count == 1)
            let star = try #require(CustomIcon.symbol("star.fill"))
            let other = CustomIconVariants(dark: star)
            _ = try legacyRecord(mixed, other, in: root)
            let before = try fileBytes(root)
            #expect(repo.variants(name: nfc) == nil)
            #expect(repo.containsRecord(name: nfc))
            #expect(repo.all.isEmpty)
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupIcon(name: nfc) }
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupRecords() }
            #expect(!repo.setVariants(pair, name: nfc))
            #expect(try fileBytes(root) == before)
            #expect(repo.setVariants(nil, name: nfc))
            #expect(!FileManager.default.fileExists(atPath: first.path))
            #expect(!FileManager.default.fileExists(atPath: second.path))
            #expect(repo.setVariants(pair, name: nfd))
            #expect(repo.variants(name: nfc) == pair)
        }
    }

    @Test("A named damaged icon blocks only its identity; empty selected files can be explicitly cleared")
    func recognizedDamage() throws {
        try withDirectory { root in
            let repo = CustomIconRepository(directory: root)
            let pair = try datePair()
            #expect(repo.setVariants(pair, name: nfc))
            let bad = legacyURL("Other", in: root)
            let malformed: [String: Any] = ["name": "Other", "icon": ["kind": "date", "value": "frozen", "backgroundHex": "#000000"]]
            try JSONSerialization.data(withJSONObject: malformed).write(to: bad, options: .atomic)
            #expect(try repo.backupIcon(name: nfd) == pair)
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupIcon(name: "Other") }
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupRecords() }
            try Data().write(to: legacyURL(nfd, in: root), options: .atomic)
            #expect(repo.variants(name: nfc) == nil)
            #expect(repo.containsRecord(name: nfc))
            #expect(repo.setVariants(nil, name: nfc))
            #expect(!repo.containsRecord(name: nfd))
            #expect(FileManager.default.fileExists(atPath: bad.path))
        }
    }

    @Test("Unattributable legacy hashes block action exports but not normal reads or website-only shares")
    func unknownDamage() throws {
        try withDirectory { root in
            let store = DiskIconBackupStorage(root: root)
            let group = SavedGroup(name: "Actions", items: [.action(name: nfc)])
            let web = SavedGroup(name: "Web", items: [.website(name: "Site", url: "https://example.com")])
            #expect(store.saveGroup(group))
            #expect(store.saveGroup(web))
            let pair = try datePair()
            #expect(store.setIcon(pair, name: nfc))
            let directory = try #require(store.icons.directory)
            // Not a plausible repository hash: scoped export can ignore this.
            try Data("broken".utf8).write(to: directory.appendingPathComponent("notes.json"))
            let engine = LibraryBackupEngine(storage: store)
            #expect(try LibraryBackup.decode(engine.exportData(groupID: group.id)).counts.icons == 1)
            // No name can be recovered from this valid old-format SHA filename.
            let opaque = legacyURL("Unknown\u{301}", in: directory)
            try Data("broken".utf8).write(to: opaque, options: .atomic)
            #expect(store.icons.variants(name: nfd) == pair)
            #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: group.id) }
            #expect(try LibraryBackup.decode(engine.exportData(groupID: web.id)).counts.icons == 0)
            try FileManager.default.removeItem(at: opaque)
            #expect(try LibraryBackup.decode(engine.exportData(groupID: group.id)).counts.icons == 1)
        }
    }

    @Test("Discovery responds to creation, same-name atomic replacement, repair and removal")
    func cacheInvalidation() throws {
        try withDirectory { root in
            let repo = CustomIconRepository(directory: root)
            #expect(repo.variants(name: nfc) == nil)
            let pair = try datePair()
            let old = try legacyRecord(mixed, pair, in: root)
            #expect(repo.variants(name: nfc) == pair)
            try Data("broken".utf8).write(to: old, options: .atomic)
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupIcon(name: nfc) }
            _ = try legacyRecord(mixed, pair, in: root)
            #expect(try repo.backupIcon(name: nfc) == pair)
            try FileManager.default.removeItem(at: old)
            #expect(repo.variants(name: nfc) == nil)
            #expect(!repo.containsRecord(name: nfc))
            #expect(try repo.backupIcon(name: nfc) == nil)
        }
    }

    @Test("Migration and clearing restore original bytes if alias cleanup fails", arguments: [false, true])
    func cleanupFailure(clearing: Bool) throws {
        try withDirectory { root in
            let pair = try datePair()
            _ = try legacyRecord(nfd, pair, in: root)
            _ = try legacyRecord(mixed, pair, in: root)
            let before = try fileBytes(root)
            let repo = CustomIconRepository(directory: root)
            var removed = 0
            let star = try #require(CustomIcon.symbol("star.fill"))
            let replacement = CustomIconVariants(standard: star)
            let result = repo.setVariants(clearing ? nil : replacement, name: nfc, removing: { url in
                removed += 1
                if removed == 2 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            })
            #expect(!result)
            #expect(removed == 2)
            #expect(try fileBytes(root) == before)
            #expect(repo.variants(name: nfc) == pair)
        }
    }

    @Test("Oversized corrupt canonical and legacy records can be cleared, with bounded on-disk rollback")
    func oversizedClear() throws {
        try withDirectory { root in
            let canonical = legacyURL(nfc, in: root)
            let legacy = legacyURL(nfd, in: root)
            let payload = Data(repeating: 0x78, count: 2 * 1_024 * 1_024)
            try payload.write(to: canonical)
            try payload.write(to: legacy)
            let repo = CustomIconRepository(directory: root)
            #expect(repo.containsRecord(name: nfc))
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupIcon(name: nfc) }
            var count = 0
            let failed = repo.setVariants(nil, name: nfc, removing: { url in
                count += 1
                if count == 2 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            })
            #expect(!failed)
            #expect(try Data(contentsOf: canonical) == payload)
            #expect(try Data(contentsOf: legacy) == payload)
            #expect(try filenames(root).count == 2)
            #expect(repo.setVariants(nil, name: nfd))
            #expect(try filenames(root).isEmpty)
            #expect(!repo.containsRecord(name: nfc))
        }
    }

    @Test("Failed compensation retains recovery links and strict exports do not hide them")
    func retainedRecovery() throws {
        try withDirectory { root in
            let pair = try datePair()
            _ = try legacyRecord(nfd, pair, in: root)
            _ = try legacyRecord(mixed, pair, in: root)
            let repo = CustomIconRepository(directory: root)
            var removed: URL?
            let result = repo.setVariants(nil, name: nfc, removing: { url in
                if let removed {
                    // A filesystem failure prevents restoring the first path.
                    try FileManager.default.createDirectory(at: removed, withIntermediateDirectories: false)
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.removeItem(at: url)
                removed = url
            })
            #expect(!result)
            let removedURL = try #require(removed)
            let recoveryName = try #require(filenames(root).first { $0.hasPrefix(".IconBackup-") })
            let recovery = root.appendingPathComponent(recoveryName).appendingPathComponent(removedURL.lastPathComponent)
            let retained = try JSONDecoder().decode(LibraryBackup.IconRecord.self, from: Data(contentsOf: recovery))
            #expect(retained.icon == pair)
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupIcon(name: "Other") }
            #expect(throws: LibraryBackupError.exportFailed) { try repo.backupRecords() }
        }
    }

    @Test("A partially failed post-commit cleanup never rolls back a valid migration or clear", arguments: [false, true])
    func committedCleanupFailure(clearing: Bool) throws {
        try withDirectory { root in
            let pair = try datePair()
            _ = try legacyRecord(nfd, pair, in: root)
            _ = try legacyRecord(mixed, pair, in: root)
            let repo = CustomIconRepository(directory: root)
            let star = try #require(CustomIcon.symbol("star.fill"))
            let replacement = CustomIconVariants(standard: star)
            var removedBackup: URL?
            let result = repo.setVariants(clearing ? nil : replacement, name: nfc, cleaningCommitted: { directory in
                let first = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
                try FileManager.default.removeItem(at: first)
                removedBackup = first
                throw CocoaError(.fileWriteNoPermission)
            })
            #expect(result)
            #expect(removedBackup != nil)
            #expect(repo.variants(name: nfd) == (clearing ? nil : replacement))
            #expect(try repo.backupIcon(name: nfc) == (clearing ? nil : replacement))
            #expect(try repo.backupRecords().count == (clearing ? 0 : 1))
            let names = try filenames(root)
            #expect(names.contains { $0.hasPrefix(".IconCleanup-") })
            #expect(!names.contains { $0.hasPrefix(".IconBackup-") })
            // A later successful no-op retries cleanup without changing artwork.
            #expect(repo.setVariants(clearing ? nil : replacement, name: nfc))
            #expect(try !filenames(root).contains { $0.hasPrefix(".IconCleanup-") })
            #expect(repo.variants(name: nfc) == (clearing ? nil : replacement))
        }
    }

    @Test("Real storage full and single-group current round trips retain both date appearances across NFC/NFD", arguments: [false, true])
    func diskBackupRoundTrip(decomposedGroup: Bool) throws {
        try withDirectory { root in
            let source = DiskIconBackupStorage(root: root.appendingPathComponent("source"))
            let groupName = decomposedGroup ? nfd : nfc
            let iconName = decomposedGroup ? nfc : nfd
            let group = SavedGroup(name: "Unicode", items: [.action(name: groupName, displayName: "Agenda")])
            #expect(source.saveGroup(group))
            let directory = try #require(source.icons.directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let pair = try datePair()
            _ = try legacyRecord(iconName, pair, in: directory)
            let before = try fileBytes(directory)
            let engine = LibraryBackupEngine(storage: source)
            for (index, data) in [try engine.exportData(), try engine.exportData(groupID: group.id)].enumerated() {
                let document = try LibraryBackup.decode(data)
                #expect(document.counts.icons == 1)
                #expect(document.icons.first?.icon == pair)
                let destination = DiskIconBackupStorage(root: root.appendingPathComponent("destination-\(index)"))
                let importer = LibraryBackupEngine(storage: destination)
                let result = importer.apply(importer.prepareImport(document))
                #expect(result.status == .completed)
                let copy = try #require(result.groups.first)
                #expect(copy.id != group.id && copy.items[0].id != group.items[0].id)
                #expect(copy.items[0].displayName == "Agenda")
                #expect(destination.icons.variants(name: nfc) == pair)
                #expect(destination.icons.variants(name: nfd) == pair)
                #expect(destination.icons.variants(name: mixed) == pair)
                #expect(try LibraryBackup.decode(importer.exportData(groupID: copy.id)).icons.first?.icon == pair)
                #expect(try fileBytes(directory) == before)
            }
        }
    }

    private func datePair() throws -> CustomIconVariants {
        let standard = try #require(CustomIcon.date(backgroundHex: "#0A84FF"))
        let dark = try #require(CustomIcon.date(backgroundHex: "#AA00FF"))
        return .init(standard: standard, dark: dark)
    }

    private func legacyURL(_ name: String, in directory: URL) -> URL {
        let oldKey = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filename = SHA256.hash(data: Data(oldKey.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
        return directory.appendingPathComponent(filename)
    }

    @discardableResult
    private func legacyRecord(_ name: String, _ pair: CustomIconVariants, in directory: URL) throws -> URL {
        let url = legacyURL(name, in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(LibraryBackup.IconRecord(name: name, icon: pair)).write(to: url, options: .atomic)
        return url
    }

    private func filenames(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func fileBytes(_ directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: filenames(directory).map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomIcon-NFC-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }
}

/// Exercises the production file repositories, including scoped strict reads;
/// unlike a String-keyed fake dictionary it cannot hide filename normalization.
final class DiskIconBackupStorage: LibraryBackupStorage {
    let groups: SavedGroupRepository
    let icons: CustomIconRepository
    let assets: FolderCoverAssetRepository
    let actionLibrary: ActionLibraryRepository
    var mappings: [String: DirectLaunchOverrides.Mapping] = [:]
    var isAvailable: Bool { true }

    init(root: URL) {
        let groupDirectory = root.appendingPathComponent("SavedGroups")
        groups = .init(directory: groupDirectory)
        icons = .init(directory: root.appendingPathComponent("CustomIcons"))
        actionLibrary = .init(directory: root.appendingPathComponent("ActionLibrary"))
        assets = .init(directory: root.appendingPathComponent("FolderCoverAssets"), groupDirectory: groupDirectory)
    }

    var snapshot: LibraryBackupSnapshot {
        .init(groups: groups.all, icons: icons.all.map { .init(name: $0.key, icon: $0.value) },
              mappings: mappings.map { .init(name: $0.key, mapping: $0.value) })
    }
    func exportSnapshot() throws -> LibraryBackupSnapshot {
        .init(groups: try groups.backupRecords(), icons: try icons.backupRecords(),
              mappings: mappings.map { .init(name: $0.key, mapping: $0.value) },
              actionLibrary: try actionLibrary.exportRecords())
    }
    func actionLibraryRecords() throws -> [ActionLibraryRecord] { try actionLibrary.exportRecords() }
    func insertActionLibraryRecords(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult { actionLibrary.insertMissing(records) }
    func rollbackActionLibraryRecords(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult {
        try actionLibrary.rollbackMatching(records)
    }
    func exportIcon(name: String) throws -> CustomIconVariants? { try icons.backupIcon(name: name) }
    func group(id: UUID) -> SavedGroup? { groups.group(id: id) }
    func icon(name: String) -> CustomIconVariants? { icons.variants(name: name) }
    func mapping(name: String) -> DirectLaunchOverrides.Mapping? { mappings[LibraryBackup.normalizedName(name)] }
    func coverAsset(id: FolderCoverAssetID) -> CustomIcon? { assets.icon(id: id) }
    func containsGroup(id: UUID) -> Bool { groups.containsRecord(id: id) }
    func containsIcon(name: String) -> Bool { icons.containsRecord(name: name) }
    func containsMapping(name: String) -> Bool { mapping(name: name) != nil }
    func containsCoverAsset(id: FolderCoverAssetID) -> Bool { assets.contains(id: id) }
    func saveGroup(_ group: SavedGroup) -> Bool { groups.save(group) }
    func removeGroup(id: UUID) -> Bool { groups.remove(id: id) }
    func setIcon(_ icon: CustomIconVariants?, name: String) -> Bool { icons.setVariants(icon, name: name) }
    func setMapping(_ mapping: DirectLaunchOverrides.Mapping?, name: String) -> Bool {
        mappings[LibraryBackup.normalizedName(name)] = mapping
        return true
    }
    func saveCoverAsset(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool { assets.save(icon, id: id) }
    func removeCoverAsset(id: FolderCoverAssetID) -> Bool { assets.remove(id: id) }
    func protectedCoverAssetIDs() throws -> Set<FolderCoverAssetID> { try assets.protectedAssetIDs() }
}
