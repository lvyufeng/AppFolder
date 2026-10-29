import Foundation

/// Kept internal so tests can inject isolated stores and deterministic failures.
/// Public operations serialize imports within this process, not across processes.
protocol LibraryBackupStorage {
    var isAvailable: Bool { get }
    var snapshot: LibraryBackupSnapshot { get }
    func exportSnapshot() throws -> LibraryBackupSnapshot
    func exportMappings(for normalizedNames: Set<String>) throws -> [LibraryBackup.MappingRecord]
    func exportIcon(name: String) throws -> CustomIconVariants?
    func actionLibraryRecords() throws -> [ActionLibraryRecord]
    func exportActionLibraryRecords(for normalizedNames: Set<String>) throws -> [ActionLibraryRecord]
    func insertActionLibraryRecords(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult
    func rollbackActionLibraryRecords(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult
    func appearancePresetRecords() throws -> [AppearancePreset]
    func insertAppearancePresetRecords(_ records: [AppearancePreset]) -> AppearancePresetInsertResult
    func rollbackAppearancePresetRecords(_ records: [AppearancePreset]) throws -> AppearancePresetRollbackResult
    func group(id: UUID) -> SavedGroup?
    func icon(name: String) -> CustomIconVariants?
    func mapping(name: String) -> DirectLaunchOverrides.Mapping?
    func coverAsset(id: FolderCoverAssetID) -> CustomIcon?
    func containsGroup(id: UUID) -> Bool
    func containsIcon(name: String) -> Bool
    func containsMapping(name: String) -> Bool
    func containsCoverAsset(id: FolderCoverAssetID) -> Bool
    func saveGroup(_ group: SavedGroup) -> Bool
    func removeGroup(id: UUID) -> Bool
    func setIcon(_ icon: CustomIconVariants?, name: String) -> Bool
    func setMapping(_ mapping: DirectLaunchOverrides.Mapping?, name: String) -> Bool
    func saveCoverAsset(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool
    func removeCoverAsset(id: FolderCoverAssetID) -> Bool
    /// Strict persistent-group and active-editor roots. Any unreadable group
    /// must fail this scan, so rollback cannot erase an unknown live reference.
    func protectedCoverAssetIDs() throws -> Set<FolderCoverAssetID>
}

extension LibraryBackupStorage {
    // Keep older injected stores source-compatible without claiming that an
    // unimplemented store has persisted a nonempty preset payload.
    func appearancePresetRecords() throws -> [AppearancePreset] { [] }
    func insertAppearancePresetRecords(_ records: [AppearancePreset]) -> AppearancePresetInsertResult {
        .init(didCommit: records.isEmpty, error: records.isEmpty ? nil : .unavailable)
    }
    func rollbackAppearancePresetRecords(_ records: [AppearancePreset]) throws -> AppearancePresetRollbackResult {
        guard records.isEmpty else { throw AppearancePresetError.unavailable }
        return .init(remainingNames: [])
    }
    func exportSnapshot() throws -> LibraryBackupSnapshot {
        var value = snapshot
        value.actionLibrary = try actionLibraryRecords()
        value.appearancePresets = try appearancePresetRecords()
        return value
    }
    func exportActionLibraryRecords(for normalizedNames: Set<String>) throws -> [ActionLibraryRecord] {
        guard !normalizedNames.isEmpty else { return [] }
        return try actionLibraryRecords().filter { normalizedNames.contains($0.id) }
    }
    func exportIcon(name: String) throws -> CustomIconVariants? {
        if let value = icon(name: name) { return value }
        guard !containsIcon(name: name) else { throw LibraryBackupError.exportFailed }
        return nil
    }
    func exportMappings(for normalizedNames: Set<String>) throws -> [LibraryBackup.MappingRecord] {
        snapshot.mappings.filter { normalizedNames.contains(LibraryBackup.normalizedName($0.name)) }
    }
}

/// Ordinary readers can omit corrupt records to keep the app usable. A backup
/// must instead fail if any library record cannot be read completely.
enum LibraryBackupRecordFiles {
    static func jsonFiles(in directory: URL?, maximumRecords: Int) throws -> [URL] {
        guard let directory else { throw LibraryBackupError.storageUnavailable }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw LibraryBackupError.exportFailed }
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return []
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        guard files.count <= maximumRecords else { throw LibraryBackupError.exportFailed }
        // Refuse an oversized library before retaining every photo in memory.
        var bytes = 0
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0,
                  size <= LibraryBackup.maximumFileBytes - bytes else { throw LibraryBackupError.exportFailed }
            bytes += size
        }
        return files
    }
}

struct LibraryBackupSnapshot {
    var groups: [SavedGroup] = []
    var icons: [LibraryBackup.IconRecord] = []
    var mappings: [LibraryBackup.MappingRecord] = []
    var actionLibrary: [ActionLibraryRecord] = []
    var appearancePresets: [AppearancePreset] = []

    var protectedNames: Set<String> {
        Set(icons.map { LibraryBackup.normalizedName($0.name) } + mappings.map { LibraryBackup.normalizedName($0.name) })
    }
}

struct LiveLibraryBackupStorage: LibraryBackupStorage {
    var isAvailable: Bool {
        SavedGroupStore.isAvailable && CustomIconStore.isAvailable && WidgetState.widgetStateIsAvailable
            && FolderCoverAssetStore.repository.isAvailable
    }

    var snapshot: LibraryBackupSnapshot {
        let names = CustomIconStore.displayNames
        return LibraryBackupSnapshot(
            groups: SavedGroupStore.all,
            icons: CustomIconStore.all.map { .init(name: names[$0.key] ?? $0.key, icon: $0.value) },
            mappings: DirectLaunchOverrides.allMappings.map { .init(name: $0.key, mapping: $0.value) }
        )
    }

    func exportSnapshot() throws -> LibraryBackupSnapshot {
        .init(groups: try SavedGroupStore.backupRecords(), icons: try CustomIconStore.backupRecords(),
              mappings: try DirectLaunchOverrides.backupRecords().map { .init(name: $0.key, mapping: $0.value) },
              actionLibrary: try actionLibraryRecords(), appearancePresets: try appearancePresetRecords())
    }

    func exportMappings(for normalizedNames: Set<String>) throws -> [LibraryBackup.MappingRecord] {
        // Mappings share one preferences value; validate that durable value,
        // then select this group's names without consulting observed slots.
        try DirectLaunchOverrides.backupRecords().compactMap {
            normalizedNames.contains(LibraryBackup.normalizedName($0.key))
                ? .init(name: $0.key, mapping: $0.value) : nil
        }
    }

    func exportIcon(name: String) throws -> CustomIconVariants? { try CustomIconStore.backupIcon(name: name) }
    func actionLibraryRecords() throws -> [ActionLibraryRecord] {
        try ActionLibraryStore.repository.exportRecords()
    }
    func exportActionLibraryRecords(for normalizedNames: Set<String>) throws -> [ActionLibraryRecord] {
        try ActionLibraryStore.repository.exportRecords(for: normalizedNames)
    }
    func insertActionLibraryRecords(_ records: [ActionLibraryRecord]) -> ActionLibraryInsertResult {
        ActionLibraryStore.repository.insertMissing(records)
    }
    func rollbackActionLibraryRecords(_ records: [ActionLibraryRecord]) throws -> ActionLibraryRollbackResult {
        try ActionLibraryStore.repository.rollbackMatching(records)
    }

    func appearancePresetRecords() throws -> [AppearancePreset] {
        try AppearancePresetStore.repository.exportRecords()
    }
    func insertAppearancePresetRecords(_ records: [AppearancePreset]) -> AppearancePresetInsertResult {
        AppearancePresetStore.repository.insertMissing(records)
    }
    func rollbackAppearancePresetRecords(_ records: [AppearancePreset]) throws -> AppearancePresetRollbackResult {
        try AppearancePresetStore.repository.rollbackMatching(records)
    }

    func group(id: UUID) -> SavedGroup? { SavedGroupStore.group(id: id) }
    func icon(name: String) -> CustomIconVariants? { CustomIconStore.variants(name: name) }
    func mapping(name: String) -> DirectLaunchOverrides.Mapping? { DirectLaunchOverrides.mapping(name: name) }
    func coverAsset(id: FolderCoverAssetID) -> CustomIcon? { FolderCoverAssetStore.repository.icon(id: id) }
    func containsGroup(id: UUID) -> Bool { SavedGroupStore.containsBackupRecord(id: id) }
    func containsIcon(name: String) -> Bool { CustomIconStore.containsBackupRecord(name: name) }
    func containsMapping(name: String) -> Bool { DirectLaunchOverrides.containsBackupRecord(name: name) }
    func containsCoverAsset(id: FolderCoverAssetID) -> Bool { FolderCoverAssetStore.repository.contains(id: id) }
    func saveGroup(_ group: SavedGroup) -> Bool { SavedGroupStore.save(group) }
    func removeGroup(id: UUID) -> Bool { SavedGroupStore.remove(id: id) }
    func setIcon(_ icon: CustomIconVariants?, name: String) -> Bool { CustomIconStore.setVariants(icon, name: name) }
    func setMapping(_ value: DirectLaunchOverrides.Mapping?, name: String) -> Bool {
        guard isAvailable else { return false }
        _ = DirectLaunchOverrides.set(mapping: value, name: name)
        return mapping(name: name) == value && (value != nil || !containsMapping(name: name))
    }
    func saveCoverAsset(_ icon: CustomIcon, id: FolderCoverAssetID) -> Bool {
        FolderCoverAssetStore.repository.save(icon, id: id)
    }
    func removeCoverAsset(id: FolderCoverAssetID) -> Bool { FolderCoverAssetStore.repository.remove(id: id) }
    func protectedCoverAssetIDs() throws -> Set<FolderCoverAssetID> {
        try FolderCoverAssetStore.repository.protectedAssetIDs()
    }
}

struct LibraryBackupEngine<Storage: LibraryBackupStorage> {
    let storage: Storage

    func exportData() throws -> Data {
        guard storage.isAvailable else { throw LibraryBackupError.storageUnavailable }
        let source: LibraryBackupSnapshot
        do { source = try storage.exportSnapshot() }
        catch { throw LibraryBackupError.exportFailed }
        return try encodeExport(source)
    }

    func exportData(groupID: UUID) throws -> Data {
        guard storage.isAvailable else { throw LibraryBackupError.storageUnavailable }
        guard let group = storage.group(id: groupID), group.id == groupID, group.isValid else {
            throw LibraryBackupError.exportFailed
        }
        let names = group.allActionNames
        let encoder = JSONEncoder()
        var bytes = try encoder.encode([group]).count
        var icons: [LibraryBackup.IconRecord] = []
        for name in names {
            if let icon = try storage.exportIcon(name: name) {
                guard icon.isValid else { throw LibraryBackupError.exportFailed }
                let record = LibraryBackup.IconRecord(name: name, icon: icon)
                let size = try encoder.encode(record).count
                guard size <= LibraryBackup.maximumFileBytes - bytes else { throw LibraryBackupError.fileTooLarge }
                bytes += size
                icons.append(record)
            }
        }
        let mappings: [LibraryBackup.MappingRecord]
        let actionLibrary: [ActionLibraryRecord]
        do {
            let normalizedNames = Set(names.map(LibraryBackup.normalizedName))
            mappings = names.isEmpty ? [] : try storage.exportMappings(for: normalizedNames)
            actionLibrary = names.isEmpty ? [] : try storage.exportActionLibraryRecords(for: normalizedNames)
        } catch { throw LibraryBackupError.exportFailed }
        return try encodeExport(.init(groups: [group], icons: icons, mappings: mappings, actionLibrary: actionLibrary))
    }

    private func encodeExport(_ source: LibraryBackupSnapshot) throws -> Data {
        let coverAssets = try exportCoverAssets(source)
        let document = LibraryBackup.Document(
            createdAt: Date(), groups: source.groups.sorted { $0.id.uuidString < $1.id.uuidString },
            icons: source.icons.sorted { $0.name < $1.name }, mappings: source.mappings.sorted { $0.name < $1.name },
            coverAssets: coverAssets, actionLibrary: source.actionLibrary.sorted { $0.id < $1.id },
            appearancePresets: source.appearancePresets.sorted { $0.id < $1.id }
        )
        return try LibraryBackup.encode(document)
    }

    private func exportCoverAssets(_ source: LibraryBackupSnapshot) throws -> [LibraryBackup.CoverAssetRecord] {
        let referenced = source.groups.reduce(into: Set<FolderCoverAssetID>()) { $0.formUnion($1.coverAssetIDs) }
        let encoder = JSONEncoder()
        // Load only referenced assets and bound their accumulated bytes before
        // retaining a large on-disk cover library. The final envelope also has
        // its own exact 32 MiB check.
        var bytes = try encoder.encode(source.groups).count + encoder.encode(source.icons).count
            + encoder.encode(source.mappings).count + encoder.encode(source.actionLibrary).count
            + encoder.encode(source.appearancePresets).count
        var assets: [LibraryBackup.CoverAssetRecord] = []
        for id in referenced.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let icon = storage.coverAsset(id: id), FolderCoverAssetRepository.id(for: icon) == id else {
                throw LibraryBackupError.exportFailed
            }
            let asset = LibraryBackup.CoverAssetRecord(id: id, icon: icon)
            let size = try encoder.encode(asset).count
            guard size <= LibraryBackup.maximumFileBytes - bytes else { throw LibraryBackupError.fileTooLarge }
            bytes += size
            assets.append(asset)
        }
        return assets
    }

    func prepareImport(_ document: LibraryBackup.Document, copyNameSuffix: String = " (Copy)") -> LibraryBackup.ImportPlan {
        let existing = storage.snapshot
        let names = existing.protectedNames
        let icons = document.icons.filter { !names.contains(LibraryBackup.normalizedName($0.name)) && !storage.containsIcon(name: $0.name) && !storage.containsMapping(name: $0.name) }
        let mappings = document.mappings.filter { !names.contains(LibraryBackup.normalizedName($0.name)) && !storage.containsIcon(name: $0.name) && !storage.containsMapping(name: $0.name) }
        let skippedIcons = document.icons.filter { record in !icons.contains { $0.name == record.name } }
        let reusedAssets = document.coverAssets.filter { storage.coverAsset(id: $0.id) == $0.icon }
        let reusedAssetIDs = Set(reusedAssets.map(\.id))
        let newAssets = document.coverAssets.filter { !reusedAssetIDs.contains($0.id) }
        let groups = document.groups.map { copy($0, suffix: copyNameSuffix) }
        // Metadata has its own conflict namespace. Existing artwork never hides
        // new tags, and incoming metadata never replaces local preferences.
        // Empty/legacy payloads do not consult the new store at all.
        let existingLibrary: [ActionLibraryRecord]? = document.actionLibrary.isEmpty ? [] : try? storage.actionLibraryRecords()
        let libraryByName = Dictionary(uniqueKeysWithValues: (existingLibrary ?? []).map { ($0.id, $0) })
        let actionLibrary = document.actionLibrary.filter { libraryByName[$0.id] == nil }
        let keptLibrary = document.actionLibrary.compactMap { libraryByName[$0.id] }
        let existingPresets: [AppearancePreset]? = document.appearancePresets.isEmpty ? [] : try? storage.appearancePresetRecords()
        let presetsByName = Dictionary(uniqueKeysWithValues: (existingPresets ?? []).map { ($0.id, $0) })
        let appearancePresets = document.appearancePresets.filter { presetsByName[$0.id] == nil }
        let keptPresets = document.appearancePresets.compactMap { presetsByName[$0.id] }
        return LibraryBackup.ImportPlan(
            groups: groups, counts: counts(groups: groups.count, icons: icons, mappings: mappings.count, coverAssets: newAssets,
                                           contactItems: groups.reduce(0) { $0 + $1.contactItemCount }, actionLibrary: actionLibrary,
                                           appearancePresets: appearancePresets),
            keptExisting: counts(groups: 0, icons: skippedIcons, mappings: document.mappings.count - mappings.count,
                                 coverAssets: reusedAssets, actionLibrary: keptLibrary, appearancePresets: keptPresets),
            isAvailable: storage.isAvailable && existingLibrary != nil && existingPresets != nil, icons: icons, mappings: mappings,
            coverAssets: document.coverAssets, actionLibrary: document.actionLibrary, appearancePresets: document.appearancePresets
        )
    }

    func apply(_ plan: LibraryBackup.ImportPlan) -> LibraryBackup.ImportResult {
        guard plan.isAvailable, storage.isAvailable else {
            // No preset store receipt exists yet. Preview conflicts are not
            // confirmation that those records remain on this device.
            let preview = plan.keptExisting
            let kept = LibraryBackup.Counts(groups: preview.groups, icons: preview.icons, photos: preview.photos,
                                            mappings: preview.mappings, folderCovers: preview.folderCovers,
                                            folderCoverPhotos: preview.folderCoverPhotos, contactItems: preview.contactItems,
                                            actionLibraryEntries: preview.actionLibraryEntries, archivedEntries: preview.archivedEntries)
            return .init(status: .unavailable, imported: .init(), keptExisting: kept, failedRecords: [], groups: [])
        }
        var protected = storage.snapshot.protectedNames
        // A corrupt record is still an existing user record and must not be overwritten.
        for name in plan.icons.map(\.name) + plan.mappings.map(\.name) {
            if storage.containsIcon(name: name) || storage.containsMapping(name: name) {
                protected.insert(LibraryBackup.normalizedName(name))
            }
        }
        var skippedIcons: [LibraryBackup.IconRecord] = []
        var skippedMappings = 0
        var skippedLibrary: [ActionLibraryRecord] = []
        var checkedLibrary = false
        var skippedPresets: [AppearancePreset] = []
        var reusedAssets: [FolderCoverAssetID: LibraryBackup.CoverAssetRecord] = [:]
        var attempts: [Record] = []
        var writtenNames = Set<String>()

        func protectedNow(_ name: String) -> Bool {
            let key = LibraryBackup.normalizedName(name)
            if protected.contains(key) { return true }
            // A matching icon and mapping from this same plan may be imported
            // together. Only records that predate this import protect the name.
            if !writtenNames.contains(key), storage.containsIcon(name: name) || storage.containsMapping(name: name) {
                protected.insert(key)
                return true
            }
            return false
        }

        func kept() -> LibraryBackup.Counts {
            .init(groups: plan.keptExisting.groups,
                  icons: plan.keptExisting.icons + skippedIcons.count,
                  photos: plan.keptExisting.photos + skippedIcons.filter { $0.icon.containsPhoto }.count,
                  mappings: plan.keptExisting.mappings + skippedMappings,
                  folderCovers: reusedAssets.count,
                  folderCoverPhotos: reusedAssets.values.filter { $0.icon.kind == .photo }.count,
                  actionLibraryEntries: checkedLibrary ? skippedLibrary.count : plan.keptExisting.actionLibraryEntries,
                  archivedEntries: checkedLibrary ? skippedLibrary.filter(\.isArchived).count : plan.keptExisting.archivedEntries,
                  appearancePresets: skippedPresets.count)
        }

        func write(_ record: Record, action: () -> Bool) -> Bool {
            // A failing write can still have left bytes behind. Include it in the
            // rollback ledger before calling the store, then verify its contents.
            attempts.append(record)
            return action() && matches(record)
        }

        // A hash identifies immutable content. Never replace a corrupt or
        // different existing file, and discover such conflicts before any write.
        var conflictingAsset: Record?
        for asset in plan.coverAssets where storage.containsCoverAsset(id: asset.id) {
            if storage.coverAsset(id: asset.id) == asset.icon { reusedAssets[asset.id] = asset }
            else if conflictingAsset == nil { conflictingAsset = .coverAsset(asset) }
        }
        if let conflictingAsset {
            return failed(conflictingAsset, attempts: [], kept: kept())
        }
        for asset in plan.coverAssets {
            let record = Record.coverAsset(asset)
            if storage.containsCoverAsset(id: asset.id) {
                guard matches(record) else { return failed(record, attempts: attempts, kept: kept()) }
                reusedAssets[asset.id] = asset
                continue
            }
            reusedAssets.removeValue(forKey: asset.id)
            guard write(record, action: { storage.saveCoverAsset(asset.icon, id: asset.id) }) else {
                return failed(record, attempts: attempts, kept: kept())
            }
        }
        for icon in plan.icons {
            if protectedNow(icon.name) { skippedIcons.append(icon); continue }
            let record = Record.icon(icon)
            guard write(record, action: { storage.setIcon(icon.icon, name: icon.name) }) else {
                return failed(record, attempts: attempts, kept: kept())
            }
            writtenNames.insert(LibraryBackup.normalizedName(icon.name))
        }
        for mapping in plan.mappings {
            if protectedNow(mapping.name) { skippedMappings += 1; continue }
            let record = Record.mapping(mapping)
            guard let value = mapping.mapping,
                  write(record, action: { storage.setMapping(value, name: mapping.name) }) else {
                return failed(record, attempts: attempts, kept: kept())
            }
            writtenNames.insert(LibraryBackup.normalizedName(mapping.name))
        }
        if !plan.actionLibrary.isEmpty {
            // One receipt owns exactly the missing names determined under the
            // metadata store lock. A failed commit can still have written bytes;
            // record its attempts before deciding whether rollback is needed.
            let receipt = storage.insertActionLibraryRecords(plan.actionLibrary)
            skippedLibrary = receipt.keptExistingRecords
            checkedLibrary = true
            if !receipt.attemptedRecords.isEmpty { attempts.append(.actionLibrary(receipt.attemptedRecords)) }
            guard receipt.didCommit, receipt.attemptedRecords.isEmpty || matches(.actionLibrary(receipt.attemptedRecords)) else {
                return failed(.actionLibrary(plan.actionLibrary), attempts: attempts, kept: kept())
            }
        }
        if !plan.appearancePresets.isEmpty {
            let receipt = storage.insertAppearancePresetRecords(plan.appearancePresets)
            skippedPresets = receipt.keptExistingRecords
            if !receipt.attemptedRecords.isEmpty { attempts.append(.appearancePresets(receipt.attemptedRecords)) }
            guard receipt.didCommit, receipt.attemptedRecords.isEmpty || matches(.appearancePresets(receipt.attemptedRecords)) else {
                return failed(.appearancePresets(plan.appearancePresets), attempts: attempts, kept: kept())
            }
        }
        for group in plan.groups {
            let record = Record.group(group)
            // Plans cannot be replayed into an existing copy or overwrite a group
            // created after the preview. The existing group never enters the ledger.
            guard !storage.containsGroup(id: group.id) else {
                return failed(record, attempts: attempts, kept: kept())
            }
            guard write(record, action: { storage.saveGroup(group) }) else {
                return failed(record, attempts: attempts, kept: kept())
            }
        }
        return .init(status: .completed, imported: counts(attempts), keptExisting: kept(),
                     failedRecords: [], groups: plan.groups)
    }

    private enum Record {
        case coverAsset(LibraryBackup.CoverAssetRecord)
        case group(SavedGroup)
        case icon(LibraryBackup.IconRecord)
        case mapping(LibraryBackup.MappingRecord)
        case actionLibrary([ActionLibraryRecord])
        case appearancePresets([AppearancePreset])

        var label: String {
            switch self {
            case .coverAsset(let asset): "Folder cover: \(asset.id.rawValue)"
            case .group(let group): "Group: \(group.name)"
            case .icon(let icon): "Icon: \(icon.name)"
            case .mapping(let mapping): "App Store: \(mapping.name)"
            case .actionLibrary: "Action library"
            case .appearancePresets: "Appearance presets"
            }
        }
    }

    private func exists(_ record: Record) -> Bool {
        switch record {
        case .coverAsset(let asset): storage.containsCoverAsset(id: asset.id)
        case .group(let group): storage.containsGroup(id: group.id)
        case .icon(let icon): storage.containsIcon(name: icon.name)
        case .mapping(let mapping): storage.containsMapping(name: mapping.name)
        case .actionLibrary(let records): !remainingLibraryRecords(records).isEmpty
        case .appearancePresets(let records): !remainingPresetRecords(records).isEmpty
        }
    }

    private func matches(_ record: Record) -> Bool {
        switch record {
        case .coverAsset(let asset): return storage.coverAsset(id: asset.id) == asset.icon
        case .group(let group): return storage.group(id: group.id) == group
        case .icon(let icon): return storage.icon(name: icon.name) == icon.icon
        case .mapping(let mapping): return storage.mapping(name: mapping.name) == mapping.mapping
        case .actionLibrary(let records):
            guard let current = try? storage.actionLibraryRecords() else { return false }
            let byName = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            return records.allSatisfy { byName[$0.id] == $0 }
        case .appearancePresets(let records):
            guard let current = try? storage.appearancePresetRecords() else { return false }
            let byName = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            return records.allSatisfy { byName[$0.id] == $0 }
        }
    }

    private func rollback(_ record: Record, protectedAssetIDs: Set<FolderCoverAssetID>?) -> Bool {
        guard exists(record) else { return true }
        // Do not erase a record another writer changed after our attempted write.
        switch record {
        case .coverAsset(let asset):
            // Assets are written first, so reverse rollback has already tried
            // every group. Keep any remaining group's or editor's references;
            // an unreadable group makes the whole reachability check uncertain.
            guard storage.coverAsset(id: asset.id) == asset.icon,
                  let protected = protectedAssetIDs,
                  !protected.contains(asset.id) else { return false }
            _ = storage.removeCoverAsset(id: asset.id)
        case .group(let group):
            if let value = storage.group(id: group.id), value != group { return false }
            _ = storage.removeGroup(id: group.id)
        case .icon(let icon):
            if let value = storage.icon(name: icon.name), value != icon.icon { return false }
            _ = storage.setIcon(nil, name: icon.name)
        case .actionLibrary(let records):
            do { return try storage.rollbackActionLibraryRecords(records).remainingNames.isEmpty }
            catch { return false }
        case .appearancePresets(let records):
            do { return try storage.rollbackAppearancePresetRecords(records).remainingNames.isEmpty }
            catch { return false }
        case .mapping(let mapping):
            // A now-unreadable country is not evidence that this remains our
            // original record. Preserve uncertain bytes and report partial.
            guard let value = storage.mapping(name: mapping.name), value == mapping.mapping else { return false }
            _ = storage.setMapping(nil, name: mapping.name)
        }
        return !exists(record)
    }

    private func failed(_ record: Record, attempts: [Record], kept: LibraryBackup.Counts) -> LibraryBackup.ImportResult {
        var failures = [record.label]
        var failureLabels: Set<String> = [record.label]
        var checkedAssetReferences = false
        var protectedAssetIDs: Set<FolderCoverAssetID>?
        for attempted in attempts.reversed() {
            if case .coverAsset = attempted, !checkedAssetReferences {
                // Asset writes precede every group write. At this point group
                // rollback is finished, and the shared operation lock keeps
                // those roots and editor leases stable through asset cleanup.
                protectedAssetIDs = try? storage.protectedCoverAssetIDs()
                checkedAssetReferences = true
            }
            if !rollback(attempted, protectedAssetIDs: protectedAssetIDs), failureLabels.insert(attempted.label).inserted {
                failures.append(attempted.label)
            }
        }
        let remaining = attempts.filter(exists)
        let groups = remaining.compactMap { record -> SavedGroup? in
            guard case .group(let group) = record else { return nil }
            return storage.group(id: group.id)
        }
        return .init(status: remaining.isEmpty ? .rolledBack : .partial,
                     imported: counts(remaining), keptExisting: kept, failedRecords: failures, groups: groups)
    }

    /// Read a metadata batch once, including changed same-name records that our
    /// rollback must preserve. An unreadable store conservatively retains the
    /// whole owned batch instead of reporting a false all-or-nothing rollback.
    private func remainingLibraryRecords(_ owned: [ActionLibraryRecord]) -> [ActionLibraryRecord] {
        guard let current = try? storage.actionLibraryRecords() else { return owned }
        let names = Set(owned.map(\.id))
        return current.filter { names.contains($0.id) }
    }

    private func remainingPresetRecords(_ owned: [AppearancePreset]) -> [AppearancePreset] {
        guard let current = try? storage.appearancePresetRecords() else { return owned }
        let names = Set(owned.map(\.id))
        return current.filter { names.contains($0.id) }
    }

    private func counts(_ records: [Record]) -> LibraryBackup.Counts {
        var groups = 0, icons = 0, photos = 0, mappings = 0, folderCovers = 0, folderCoverPhotos = 0, contactItems = 0
        var actionLibraryEntries = 0, archivedEntries = 0, appearancePresets = 0
        for record in records {
            switch record {
            case .coverAsset(let asset):
                folderCovers += 1
                if (storage.coverAsset(id: asset.id) ?? asset.icon).kind == .photo { folderCoverPhotos += 1 }
            case .group(let value):
                groups += 1
                // Like photo counts, a partial result retains the attempted
                // payload's count when remaining bytes cannot be read back.
                contactItems += (storage.group(id: value.id) ?? value).contactItemCount
            case .icon(let value):
                icons += 1
                if (storage.icon(name: value.name) ?? value.icon).containsPhoto { photos += 1 }
            case .mapping: mappings += 1
            case .actionLibrary(let owned):
                let remaining = remainingLibraryRecords(owned)
                actionLibraryEntries += remaining.count
                archivedEntries += remaining.filter(\.isArchived).count
            case .appearancePresets(let owned):
                appearancePresets += remainingPresetRecords(owned).count
            }
        }
        return .init(groups: groups, icons: icons, photos: photos, mappings: mappings,
                     folderCovers: folderCovers, folderCoverPhotos: folderCoverPhotos, contactItems: contactItems,
                     actionLibraryEntries: actionLibraryEntries, archivedEntries: archivedEntries,
                     appearancePresets: appearancePresets)
    }

    private func counts(groups: Int, icons: [LibraryBackup.IconRecord], mappings: Int,
                        coverAssets: [LibraryBackup.CoverAssetRecord] = [], contactItems: Int = 0,
                        actionLibrary: [ActionLibraryRecord] = [], appearancePresets: [AppearancePreset] = []) -> LibraryBackup.Counts {
        .init(groups: groups, icons: icons.count, photos: icons.filter { $0.icon.containsPhoto }.count, mappings: mappings,
              folderCovers: coverAssets.count, folderCoverPhotos: coverAssets.filter { $0.icon.kind == .photo }.count,
              contactItems: contactItems, actionLibraryEntries: actionLibrary.count,
              archivedEntries: actionLibrary.filter(\.isArchived).count, appearancePresets: appearancePresets.count)
    }

    private func copy(_ original: SavedGroup, suffix rawSuffix: String) -> SavedGroup {
        var suffix = String(rawSuffix.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        suffix = String(suffix.prefix(20))
        while suffix.utf8.count > 128 { suffix.removeLast() }
        let ending = " " + String((suffix.isEmpty ? "(Copy)" : suffix).prefix(20))
        var base = original.name
        // Only the display name is shortened when needed to append the suffix;
        // the confirmation preview shows it. No records or tree nodes are dropped.
        while !base.isEmpty && ((base + ending).count > SavedGroup.maximumNameLength || (base + ending).utf8.count > 512) {
            base.removeLast()
        }
        func nodes(_ items: [GroupItem]) -> [GroupItem] {
            items.map {
                .init(id: UUID(), kind: $0.kind, name: $0.name,
                      children: nodes($0.children), displayName: $0.displayName, folderCover: $0.folderCover,
                      websiteURL: $0.websiteURL, websiteIcon: $0.websiteIcon,
                      folderAppearance: $0.folderAppearance, folderPreviewGrid: $0.folderPreviewGrid,
                      contactTarget: $0.contactTarget, contactIcon: $0.contactIcon,
                      websiteBrowser: $0.websiteBrowser)
            }
        }
        return SavedGroup(id: UUID(), name: base + ending, items: nodes(original.items), updatedAt: Date(),
                          appearance: original.appearance)
    }
}
