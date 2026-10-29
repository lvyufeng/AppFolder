import Foundation
import Testing
@testable import AppFolderKit

@Suite("Appearance preset backup version fifteen")
struct LibraryBackupAppearancePresetTests {
    @Test("Full backups include unused presets; single-group shares retain only embedded appearances")
    func fullAndScoped() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = PresetBackupStorage(directory: root)
        let preset = preset("Unused")
        #expect(source.repository.insertMissing([preset]).didCommit)
        let folder = GroupItem.folder(name: "Nested", children: [.website(name: "Site", url: "https://example.org")],
                                      folderAppearance: .init(grid: .four, plate: .solid, tintHex: "#123456"))
        let group = SavedGroup(name: "Group", items: [folder], appearance: .init(showsTitles: false, iconSize: .large))
        source.base.groups[group.id] = group
        let exporter = LibraryBackupEngine(storage: source)
        let data = try exporter.exportData()
        let json = try object(data)
        #expect(json["version"] as? Int == 16)
        let full = try LibraryBackup.decode(data)
        #expect(full.appearancePresets == [preset] && full.counts.appearancePresets == 1)
        #expect(full.groups == [group])
        source.presetReads = 0
        let scoped = try LibraryBackup.decode(exporter.exportData(groupID: group.id))
        #expect(scoped.appearancePresets.isEmpty && scoped.counts.appearancePresets == 0)
        #expect(scoped.groups == [group] && source.presetReads == 0)
        try source.corruptPresets()
        #expect(throws: LibraryBackupError.exportFailed) { try exporter.exportData() }
        source.presetReads = 0
        #expect(try LibraryBackup.decode(exporter.exportData(groupID: group.id)).groups == [group])
        #expect(source.presetReads == 0)
    }

    @Test("Preset-only backups round trip the maximum batch without changing existing group appearance")
    func presetOnlyRoundTrip() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = PresetBackupStorage(directory: root.appendingPathComponent("source"))
        let records = (0..<AppearancePresetRepository.maximumRecords).map { preset("Preset \($0)") }
        #expect(source.repository.insertMissing(records).didCommit)
        let document = try LibraryBackup.decode(LibraryBackupEngine(storage: source).exportData())
        #expect(document.groups.isEmpty && document.counts == .init(appearancePresets: records.count))
        let destination = PresetBackupStorage(directory: root.appendingPathComponent("destination"))
        let original = SavedGroup(name: "Keep appearance", items: [.website(name: "Web", url: "https://example.org")],
                                  appearance: .init(grid: .four, tintHex: "#00FF00"))
        destination.base.groups[original.id] = original
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document)
        #expect(plan.appearancePresets.count == records.count && plan.counts.appearancePresets == records.count)
        let result = importer.apply(plan)
        #expect(result.status == .completed && result.imported == .init(appearancePresets: records.count))
        #expect(result.keptExisting.appearancePresets == 0 && destination.presetInserts == 1)
        #expect(try destination.repository.exportRecords().sorted { $0.id < $1.id } == records.sorted { $0.id < $1.id })
        #expect(destination.base.groups == [original.id: original])
    }

    @Test("Versions one through fourteen omit presets and never consult their unavailable store", arguments: Array(1...14))
    func legacy(version: Int) throws {
        var json = try object(LibraryBackup.encode(document([])))
        json["version"] = version
        json.removeValue(forKey: "appearancePresets")
        if version < 12 { json.removeValue(forKey: "actionLibrary") }
        if version < 5 { json.removeValue(forKey: "coverAssets") }
        let legacy = try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
        #expect(legacy.appearancePresets.isEmpty && legacy.counts.appearancePresets == 0)
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        try destination.corruptPresets()
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(legacy)
        let result = importer.apply(plan)
        #expect(plan.isAvailable && result.status == .completed)
        #expect(destination.presetReads == 0 && destination.presetInserts == 0 && destination.presetRollbacks == 0)
        for forbidden: Any in [[], NSNull(), [["name": "Injected"]]] {
            json["appearancePresets"] = forbidden
            #expect(throws: LibraryBackupError.invalidContents) {
                try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json))
            }
        }
    }

    @Test("Version fifteen requires a bounded, unique, valid preset array")
    func strictSchema() throws {
        let original = try object(LibraryBackup.encode(document([preset("Caf\u{e9}")])))
        var missing = original
        missing.removeValue(forKey: "appearancePresets")
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: missing)) }
        let valid = try #require((original["appearancePresets"] as? [[String: Any]])?.first)
        var duplicate = valid
        duplicate["name"] = "CAF\u{e9}"
        var invalidRecords: [[String: Any]] = []
        for name in ["", " ", " padded ", "Control\n", String(repeating: "a", count: 65), String(repeating: "\u{1F9D1}\u{1F3FF}\u{200D}\u{1F680}", count: 20)] {
            var record = valid
            record["name"] = name
            invalidRecords.append(record)
        }
        var unknown = valid
        unknown["url"] = "https://example.org"
        invalidRecords.append(unknown)
        for field in ["grid", "plate", "tintHex", "iconSize", "density", "backButtonStyle"] {
            var record = valid
            var appearance = try #require(record["appearance"] as? [String: Any])
            appearance[field] = "invalid"
            record["appearance"] = appearance
            invalidRecords.append(record)
        }
        var invalidPayloads: [Any] = [NSNull(), "not an array", [valid, duplicate], Array(repeating: valid, count: 65)]
        invalidPayloads += invalidRecords.map { [$0] }
        for payload in invalidPayloads {
            var json = original
            json["appearancePresets"] = payload
            #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.decode(JSONSerialization.data(withJSONObject: json)) }
        }
        var empty = original
        empty["appearancePresets"] = []
        #expect(try LibraryBackup.decode(JSONSerialization.data(withJSONObject: empty)).counts.appearancePresets == 0)
        #expect(throws: LibraryBackupError.invalidContents) { try LibraryBackup.encode(document([preset("" )])) }
    }

    @Test("Existing normalized names win even when they contain the identical incoming value")
    func existingWins() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let identical = preset("Same")
        let incoming = preset("Caf\u{e9}")
        let local = preset("CAF\u{e9}", color: "#001122")
        #expect(destination.repository.insertMissing([identical, local]).didCommit)
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document([identical, incoming]))
        #expect(plan.counts.appearancePresets == 0 && plan.keptExisting.appearancePresets == 2)
        #expect(plan.appearancePresets == [identical, incoming])
        let result = importer.apply(plan)
        #expect(result.status == .completed && result.imported.appearancePresets == 0)
        #expect(result.keptExisting.appearancePresets == 2 && destination.presetRollbacks == 0)
        #expect(try destination.repository.exportRecords().sorted { $0.id < $1.id } == [identical, local].sorted { $0.id < $1.id })
    }

    @Test("A name inserted after preview is kept by the locked receipt rather than owned by the plan")
    func lateConflict() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let incoming = preset("Late")
        let local = preset("LATE", color: "#00AA00")
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document([incoming]))
        #expect(plan.counts.appearancePresets == 1)
        destination.beforeInsert = { #expect(destination.repository.insertMissing([local]).didCommit) }
        let result = importer.apply(plan)
        #expect(result.status == .completed && result.imported.appearancePresets == 0 && result.keptExisting.appearancePresets == 1)
        #expect(try destination.repository.exportRecords() == [local])
    }

    @Test("Preview conflicts are rechecked after an edit or deletion and are not treated as commit facts")
    func previewIsNotCommit() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let incoming = preset("Same")
        let local = preset("Same", color: "#001122")
        #expect(destination.repository.insertMissing([local]).didCommit)
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document([incoming]))
        #expect(plan.keptExisting.appearancePresets == 1)
        let changed = preset("Same", color: "#332211")
        _ = try destination.repository.apply([.init(name: local.name, expected: local, replacement: changed)])
        let kept = importer.apply(plan)
        #expect(kept.status == .completed && kept.keptExisting.appearancePresets == 1 && kept.imported.appearancePresets == 0)
        #expect(try destination.repository.exportRecords() == [changed])
        _ = try destination.repository.apply([.init(name: changed.name, expected: changed, replacement: nil)])
        let restored = importer.apply(plan)
        #expect(restored.status == .completed && restored.imported.appearancePresets == 1 && restored.keptExisting.appearancePresets == 0)
        try destination.corruptPresets()
        let failed = importer.apply(plan)
        #expect(failed.status == .rolledBack && failed.imported.appearancePresets == 0 && failed.keptExisting.appearancePresets == 0)
        let unavailable = importer.prepareImport(document([incoming]))
        #expect(!unavailable.isAvailable && importer.apply(unavailable).status == .unavailable)
        #expect(importer.apply(unavailable).keptExisting.appearancePresets == 0)
    }

    @Test("A later group failure rolls back owned presets in one batch and preserves existing names")
    func groupFailureRollsBack() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let local = preset("Keep")
        let incoming = preset("New")
        #expect(destination.repository.insertMissing([local]).didCommit)
        destination.base.failWrite = 1
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document([local, incoming], groups: [group()])))
        #expect(result.status == .rolledBack && result.imported == .init())
        #expect(result.keptExisting.appearancePresets == 1 && destination.presetRollbacks == 1)
        #expect(try destination.repository.exportRecords() == [local])
        #expect(destination.base.groups.isEmpty)
    }

    @Test("Rollback preserves a later same-name edit and reports only the records actually remaining")
    func changedOwnedRecordRemainsPartial() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let first = preset("First")
        let second = preset("Second")
        let changed = preset("FIRST", color: "#000000")
        destination.base.failWrite = 1
        destination.base.onFailure = {
            _ = try? destination.repository.apply([.init(name: first.name, expected: first, replacement: changed)])
        }
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document([first, second], groups: [group()])))
        #expect(result.status == .partial && result.imported == .init(appearancePresets: 1))
        #expect(result.failedRecords.contains("Appearance presets"))
        #expect(try destination.repository.exportRecords() == [changed])
        #expect(destination.base.groups.isEmpty)
    }

    @Test("An unconfirmed preset receipt owns only its attempted new rows, including already persisted bytes")
    func failedReceiptOwnership() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let existing = preset("Existing")
        let new = preset("New")
        let importer = LibraryBackupEngine(storage: destination)
        let plan = importer.prepareImport(document([existing, new]))
        #expect(plan.counts.appearancePresets == 2)
        #expect(destination.repository.insertMissing([existing]).didCommit)
        destination.failCommittedPresetInsert = true
        let result = importer.apply(plan)
        #expect(result.status == .rolledBack && result.imported.appearancePresets == 0)
        #expect(result.keptExisting.appearancePresets == 1 && destination.presetRollbacks == 1)
        #expect(try destination.repository.exportRecords() == [existing])
    }

    @Test("Unreadable rollback retains an uncertain owned count and never reports all-or-nothing success")
    func unreadableRollback() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        destination.base.failWrite = 1
        destination.base.onFailure = { try? destination.corruptPresets() }
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document([preset("One"), preset("Two")], groups: [group()])))
        #expect(result.status == .partial && result.imported.appearancePresets == 2)
        #expect(destination.presetRollbacks == 1 && result.failedRecords.contains("Appearance presets"))
    }

    @Test("A full destination rejects new rows without claiming or erasing any existing preset")
    func destinationCapacity() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = PresetBackupStorage(directory: root)
        let records = (0..<64).map { preset("Local \($0)") }
        #expect(destination.repository.insertMissing(records).didCommit)
        let importer = LibraryBackupEngine(storage: destination)
        let result = importer.apply(importer.prepareImport(document([records[0], preset("Extra")], groups: [group()])))
        #expect(result.status == .rolledBack && result.imported == .init() && result.keptExisting.appearancePresets == 1)
        #expect(destination.presetRollbacks == 0 && destination.base.groups.isEmpty)
        #expect(try destination.repository.exportRecords().count == 64)
    }

    @Test("A source-compatible older injected store cannot silently accept nonempty presets")
    func olderStorageCannotSwallowPresets() throws {
        let importer = LibraryBackupEngine(storage: BackupTestStorage())
        let result = importer.apply(importer.prepareImport(document([preset("Incoming")])))
        #expect(result.status == .rolledBack && result.imported.appearancePresets == 0)
        #expect(result.failedRecords == ["Appearance presets"])
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("preset-backup-" + UUID().uuidString)
    }
    private func preset(_ name: String, color: String = "#123456") -> AppearancePreset {
        .init(name: name, appearance: .init(grid: .four, showsTitles: false, iconSize: .large,
                                          plate: .automatic, tintHex: color, density: .spacious, backButtonStyle: .folder))
    }
    private func document(_ presets: [AppearancePreset], groups: [SavedGroup] = []) -> LibraryBackup.Document {
        .init(createdAt: Date(), groups: groups, icons: [], mappings: [], appearancePresets: presets)
    }
    private func group() -> SavedGroup {
        .init(name: "Group", items: [.website(name: "Site", url: "https://example.org")])
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Exercise the production preset repository while delegating unrelated storage
/// and deterministic group-write failures to the existing backup test store.
final class PresetBackupStorage: LibraryBackupStorage {
    let base = BackupTestStorage()
    var repository: AppearancePresetRepository
    var presetReads = 0
    var presetInserts = 0
    var presetRollbacks = 0
    var beforeInsert: (() -> Void)?
    var failCommittedPresetInsert = false

    init(directory: URL) { repository = .init(directory: directory) }
    var isAvailable: Bool { base.isAvailable }
    var snapshot: LibraryBackupSnapshot { base.snapshot }
    func exportSnapshot() throws -> LibraryBackupSnapshot {
        var value = try base.exportSnapshot()
        value.appearancePresets = try appearancePresetRecords()
        return value
    }
    func appearancePresetRecords() throws -> [AppearancePreset] {
        presetReads += 1
        return try repository.exportRecords()
    }
    func insertAppearancePresetRecords(_ records: [AppearancePreset]) -> AppearancePresetInsertResult {
        presetInserts += 1
        beforeInsert?()
        let receipt = repository.insertMissing(records)
        // Inject an unconfirmed response after durable bytes have been written.
        // Receipt ownership still comes from the repository's locked read.
        guard failCommittedPresetInsert else { return receipt }
        return .init(didCommit: false, attemptedRecords: receipt.attemptedRecords,
                     keptExistingRecords: receipt.keptExistingRecords, error: .writeFailed)
    }
    func rollbackAppearancePresetRecords(_ records: [AppearancePreset]) throws -> AppearancePresetRollbackResult {
        presetRollbacks += 1
        return try repository.rollbackMatching(records)
    }
    func corruptPresets() throws {
        let directory = try #require(repository.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }
    func actionLibraryRecords() throws -> [ActionLibraryRecord] { try base.actionLibraryRecords() }
    func insertActionLibraryRecords(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult { base.insertActionLibraryRecords(records) }
    func rollbackActionLibraryRecords(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult { try base.rollbackActionLibraryRecords(records) }
    func group(id: UUID) -> SavedGroup? { base.group(id: id) }
    func icon(name: String) -> CustomIconVariants? { base.icon(name: name) }
    func mapping(name: String) -> DirectLaunchOverrides.Mapping? { base.mapping(name: name) }
    func coverAsset(id: FolderCoverAssetID) -> CustomIcon? { base.coverAsset(id: id) }
    func containsGroup(id: UUID) -> Bool { base.containsGroup(id: id) }
    func containsIcon(name: String) -> Bool { base.containsIcon(name: name) }
    func containsMapping(name: String) -> Bool { base.containsMapping(name: name) }
    func containsCoverAsset(id: FolderCoverAssetID) -> Bool { base.containsCoverAsset(id: id) }
    func saveGroup(_ group: SavedGroup) -> Bool { base.saveGroup(group) }
    func removeGroup(id: UUID) -> Bool { base.removeGroup(id: id) }
    func setIcon(_ icon: CustomIconVariants?, name: String) -> Bool { base.setIcon(icon, name: name) }
    func setMapping(_ mapping: DirectLaunchOverrides.Mapping?, name: String) -> Bool { base.setMapping(mapping, name: name) }
    func saveCoverAsset(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool { base.saveCoverAsset(icon, id: id) }
    func removeCoverAsset(id: FolderCoverAssetID) -> Bool { base.removeCoverAsset(id: id) }
    func protectedCoverAssetIDs() throws -> Set<FolderCoverAssetID> { try base.protectedCoverAssetIDs() }
}
