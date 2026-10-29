import Foundation
import Testing
@testable import AppFolderKit

@Suite("Action library backup version twelve")
struct LibraryBackupActionLibraryTests {
    @Test("Full backups retain unused and archived manual names; single-group shares include only action references")
    func fullAndScoped() throws {
        let source = try BackupTestStorage.fixture()
        let id = try #require(source.groups.keys.first)
        let used = try record("Camera", tags: ["Photos"], archived: true)
        let unused = try record("Manual unused")
        let archived = try record("Archived unused", tags: ["Later"], archived: true)
        source.actionLibrary = [used.id: used, unused.id: unused, archived.id: archived]
        source.groups[id]?.items.append(.website(name: unused.name, url: "https://example.com"))
        let engine = LibraryBackupEngine(storage: source)
        let full = try LibraryBackup.decode(engine.exportData())
        #expect(full.actionLibrary.sorted { $0.id < $1.id } == [used, unused, archived].sorted { $0.id < $1.id })
        #expect(full.counts.actionLibraryEntries == 3 && full.counts.archivedEntries == 2)
        let scoped = try LibraryBackup.decode(engine.exportData(groupID: id))
        #expect(scoped.actionLibrary == [used])
        #expect(scoped.groups.first?.allActionNames == ["Camera"])
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(full))
        #expect(result.status == .completed && result.imported.actionLibraryEntries == 3)
        #expect(result.imported.archivedEntries == 2 && destination.actionLibrary == source.actionLibrary)
        let copied = try #require(result.groups.first)
        #expect(copied.id != id && copied.allActionNames == source.groups[id]?.allActionNames)
        #expect(copied.items[0].id != source.groups[id]?.items[0].id)
    }

    @Test("Metadata-only backups use real repositories and preserve empty manual records")
    func metadataOnlyDiskRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = DiskIconBackupStorage(root: root.appendingPathComponent("source"))
        let records = [try record("Unused empty"), try record("归档动作", tags: ["以后"], archived: true)]
        #expect(source.actionLibrary.insertMissing(records).didCommit)
        let data = try LibraryBackupEngine(storage: source).exportData()
        let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(envelope["version"] as? Int == 16)
        let document = try LibraryBackup.decode(data)
        #expect(document.groups.isEmpty && document.counts.icons == 0 && document.counts.actionLibraryEntries == 2)
        let destination = DiskIconBackupStorage(root: root.appendingPathComponent("destination"))
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .completed && result.imported.actionLibraryEntries == 2)
        #expect(result.imported.archivedEntries == 1)
        #expect(try destination.actionLibrary.exportRecords().sorted { $0.id < $1.id } == records.sorted { $0.id < $1.id })
    }

    @Test("Metadata conflicts are independent from icon and mapping conflicts")
    func independentNamespaces() throws {
        let source = try BackupTestStorage.fixture()
        let incoming = try record("Camera", tags: ["Incoming"], archived: false)
        source.actionLibrary[incoming.id] = incoming
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let artworkOwner = BackupTestStorage()
        artworkOwner.icons["camera"] = .init(standard: .emoji("A"))
        let first = LibraryBackupEngine(storage: artworkOwner)
        let result = first.apply(first.prepareImport(document))
        #expect(result.status == .completed && result.imported.actionLibraryEntries == 1)
        #expect(artworkOwner.actionLibrary[incoming.id] == incoming)
        #expect(artworkOwner.icons["camera"]?.standard == .emoji("A") && artworkOwner.mappings.isEmpty)
        let metadataOwner = BackupTestStorage()
        let local = try record(" CAMERA ", tags: ["Local"], archived: true)
        metadataOwner.actionLibrary[local.id] = local
        let second = LibraryBackupEngine(storage: metadataOwner)
        let preserved = second.apply(second.prepareImport(document))
        #expect(preserved.status == .completed && preserved.imported.actionLibraryEntries == 0)
        #expect(preserved.keptExisting.actionLibraryEntries == 1 && preserved.keptExisting.archivedEntries == 1)
        #expect(metadataOwner.actionLibrary[local.id] == local)
        #expect(metadataOwner.icons["camera"] == source.icons["camera"] && metadataOwner.mappings["camera"] == 123456)
    }

    @Test("Canonical Unicode names collide once, and a record added after preview is preserved")
    func unicodeAndLateConflict() throws {
        let source = BackupTestStorage()
        let incoming = try record("Cafe\u{301}", tags: ["Incoming"])
        source.actionLibrary[incoming.id] = incoming
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        #expect(plan.counts.actionLibraryEntries == 1)
        let local = try record(" CAFÉ ", tags: ["Keep"], archived: true)
        destination.actionLibrary[local.id] = local
        let result = importer.apply(plan)
        #expect(result.status == .completed && result.imported.actionLibraryEntries == 0)
        #expect(result.keptExisting.actionLibraryEntries == 1 && result.keptExisting.archivedEntries == 1)
        #expect(destination.actionLibrary == [local.id: local])
        #expect(destination.actionLibraryInsertCalls == 1 && destination.writes == 0)
    }

    @Test("Records kept at preview are rechecked after archive changes, deletion or corruption")
    func previouslyKeptRecordsAreRechecked() throws {
        let source = BackupTestStorage()
        let incoming = try record("Same", tags: ["Incoming"])
        source.actionLibrary[incoming.id] = incoming
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let local = try record("Same", tags: ["Local"])
        destination.actionLibrary[local.id] = local
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        #expect(plan.counts.actionLibraryEntries == 0 && plan.keptExisting.actionLibraryEntries == 1)
        let archived = try record("Same", tags: ["Changed"], archived: true)
        destination.actionLibrary[archived.id] = archived
        let updated = importer.apply(plan)
        #expect(updated.status == .completed && updated.keptExisting.archivedEntries == 1)
        #expect(updated.imported.actionLibraryEntries == 0 && destination.actionLibrary[local.id] == archived)
        destination.actionLibrary.removeValue(forKey: local.id)
        let restored = importer.apply(plan)
        #expect(restored.status == .completed && restored.imported.actionLibraryEntries == 1)
        #expect(restored.keptExisting.actionLibraryEntries == 0 && destination.actionLibrary[incoming.id] == incoming)
        destination.unreadableActionLibrary = true
        let rejected = importer.apply(plan)
        #expect(rejected.status == .rolledBack && rejected.keptExisting.actionLibraryEntries == 0)
        #expect(destination.actionLibrary[incoming.id] == incoming)
    }

    @Test("Web-only scoped shares bypass broken metadata; full and action-scoped shares fail strictly")
    func strictReadsAndScope() throws {
        let source = BackupTestStorage()
        let web = SavedGroup(name: "Web", items: [.website(name: "Site", url: "https://example.com")])
        let action = SavedGroup(name: "Actions", items: [.action(name: "Camera")])
        source.groups = [web.id: web, action.id: action]
        source.unreadableActionLibrary = true
        let engine = LibraryBackupEngine(storage: source)
        #expect(try LibraryBackup.decode(engine.exportData(groupID: web.id)).actionLibrary.isEmpty)
        #expect(source.actionLibraryReads == 0)
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData(groupID: action.id) }
        #expect(throws: LibraryBackupError.exportFailed) { try engine.exportData() }
    }

    @Test("Versions one through eleven remain readable and import without consulting the new store", arguments: Array(1...11))
    func legacy(version: Int) throws {
        let source = try BackupTestStorage.fixture()
        var json = try object(LibraryBackupEngine(storage: source).exportData())
        json["version"] = version
        json.removeValue(forKey: "appearancePresets")
        json.removeValue(forKey: "actionLibrary")
        if version < 5 { json.removeValue(forKey: "coverAssets") }
        let document = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
        #expect(document.actionLibrary.isEmpty && document.counts.actionLibraryEntries == 0)
        let destination = BackupTestStorage()
        destination.unreadableActionLibrary = true
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .completed && destination.groups.count == 1)
        #expect(destination.actionLibraryReads == 0 && destination.actionLibraryInsertCalls == 0)
    }

    @Test("Older envelopes reject the new field even when empty or null", arguments: Array(1...11))
    func rejectsDowngrade(version: Int) throws {
        let source = BackupTestStorage()
        var json = try object(LibraryBackupEngine(storage: source).exportData())
        json["version"] = version
        json.removeValue(forKey: "appearancePresets")
        if version < 5 { json.removeValue(forKey: "coverAssets") }
        for value: Any in [[], NSNull()] {
            json["actionLibrary"] = value
            #expect(throws: LibraryBackupError.invalidContents) {
                try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
            }
        }
    }

    @Test("V12 requires a valid bounded array without normalized duplicate names or unknown fields")
    func strictSchema() throws {
        let source = BackupTestStorage()
        let entry = try record("Café", tags: ["Work"])
        source.actionLibrary[entry.id] = entry
        let original = try object(LibraryBackupEngine(storage: source).exportData())
        var missing = original
        missing.removeValue(forKey: "actionLibrary")
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: missing)) }
        let validRecord = try #require((original["actionLibrary"] as? [[String: Any]])?.first)
        var duplicate = validRecord
        duplicate["name"] = "CAFÉ"
        var unexpected = validRecord
        unexpected["systemShortcut"] = "not allowed"
        for invalid: Any in [NSNull(), "not an array", [validRecord, duplicate], [unexpected],
                             Array(repeating: validRecord, count: ActionLibraryRepository.maximumRecords + 1)] {
            var json = original
            json["actionLibrary"] = invalid
            #expect(throws: LibraryBackupError.invalidContents) {
                try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
            }
        }
    }

    @Test("Maximum-size metadata import performs one batch write and bounded reads")
    func batchDoesNotRewritePerRecord() throws {
        let source = BackupTestStorage()
        for index in 0..<ActionLibraryRepository.maximumRecords {
            let entry = try record("Manual \(index)", tags: ["Batch"], archived: index.isMultiple(of: 2))
            source.actionLibrary[entry.id] = entry
        }
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .completed && result.imported.actionLibraryEntries == ActionLibraryRepository.maximumRecords)
        #expect(result.imported.archivedEntries == ActionLibraryRepository.maximumRecords / 2)
        #expect(destination.actionLibraryInsertCalls == 1 && destination.writes == 1)
        #expect(destination.actionLibraryReads <= 3)
    }

    @Test("Later group failure rolls back the whole metadata batch and earlier artwork")
    func rollbackAfterGroupFailure() throws {
        let source = try BackupTestStorage.fixture()
        let entry = try record("Unused", archived: true)
        source.actionLibrary[entry.id] = entry
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.failWrite = 4 // icon, mapping, metadata batch, group
        destination.persistBeforeFailure = true
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .rolledBack && result.imported == .init())
        #expect(destination.groups.isEmpty && destination.icons.isEmpty && destination.mappings.isEmpty && destination.actionLibrary.isEmpty)
        #expect(destination.actionLibraryRollbackCalls == 1)
    }

    @Test("Failed batch receipt never owns an existing record, including a late identical one")
    func batchFailureOwnership() throws {
        let source = BackupTestStorage()
        let existing = try record("Same", tags: ["Keep"], archived: true)
        let new = try record("New")
        source.actionLibrary = [existing.id: existing, new.id: new]
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        destination.actionLibrary[existing.id] = existing
        destination.failWrite = 1
        destination.persistBeforeFailure = true
        let result = importer.apply(plan)
        #expect(result.status == .rolledBack && result.imported.actionLibraryEntries == 0)
        #expect(result.keptExisting.actionLibraryEntries == 1 && destination.actionLibrary == [existing.id: existing])
        #expect(destination.actionLibraryRollbackCalls == 1)
    }

    @Test("Rollback preserves changed owned records and reports actual remaining archived counts")
    func rollbackPreservesNewerEdits() throws {
        let source = BackupTestStorage()
        let first = try record("First")
        let second = try record("Second", archived: true)
        source.actionLibrary = [first.id: first, second.id: second]
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let changed = try record("First", tags: ["Local edit"], archived: true)
        let destination = BackupTestStorage()
        destination.failWrite = 1
        destination.persistBeforeFailure = true
        destination.onFailure = { destination.actionLibrary[first.id] = changed }
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document))
        #expect(result.status == .partial && result.imported.actionLibraryEntries == 1 && result.imported.archivedEntries == 1)
        #expect(destination.actionLibrary == [changed.id: changed])
    }

    @Test("Unreadable metadata blocks metadata imports, and uncertain rollback is reported as partial")
    func unreadableImportAndRollback() throws {
        let source = BackupTestStorage()
        let entry = try record("Owned", archived: true)
        source.actionLibrary[entry.id] = entry
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        let destination = BackupTestStorage()
        destination.unreadableActionLibrary = true
        let importer = LibraryBackupEngine(storage: destination)
        #expect(!importer.prepareImport(document).isAvailable)
        destination.unreadableActionLibrary = false
        let plan = importer.prepareImport(document)
        destination.unreadableActionLibrary = true
        #expect(importer.apply(plan).status == .rolledBack)
        #expect(destination.writes == 0 && destination.actionLibraryRollbackCalls == 0)
        destination.unreadableActionLibrary = false
        destination.failWrite = 1
        destination.persistBeforeFailure = true
        destination.onFailure = { destination.unreadableActionLibrary = true }
        let result = importer.apply(plan)
        #expect(result.status == .partial && result.imported.actionLibraryEntries == 1 && result.imported.archivedEntries == 1)
        #expect(destination.actionLibrary[entry.id] == entry)
    }

    private func record(_ name: String, tags: [String] = [], archived: Bool = false) throws -> ActionLibraryRecord {
        try #require(ActionLibraryRecord(name: name, tags: tags, isArchived: archived))
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
