import Foundation

public enum LibraryBackupError: Error, Sendable, Equatable, LocalizedError {
    case fileTooLarge
    case unsupportedVersion(Int)
    case invalidFormat
    case invalidContents
    case storageUnavailable
    case readFailed
    case exportFailed

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge: "The backup exceeds the 32 MiB limit."
        case .unsupportedVersion: "This backup version is not supported."
        case .invalidFormat: "This is not an AppFolder library backup."
        case .invalidContents: "The backup contains invalid or duplicate records."
        case .storageUnavailable: "The shared library is unavailable."
        case .readFailed: "The backup file could not be read."
        case .exportFailed: "The library could not be exported."
        }
    }
}

/// A single versioned file containing durable user choices only. It contains no
/// SystemShortcut tokens, widget configuration, downloaded caches, or diagnostics.
public enum LibraryBackup {
    public static let maximumFileBytes = 32 * 1_024 * 1_024
    static let format = "appfolder.library"
    // Version 16 adds explicit spacing, margins, and title color/outline choices.
    // Older apps must reject exports rather than silently discard those choices.
    static let version = 16
    static let maximumGroups = 1_000
    static let maximumIcons = 2_048
    static let maximumMappings = 10_000

    public struct Counts: Sendable, Equatable {
        public let groups: Int
        public let icons: Int
        /// Action-icon records containing a photo in either appearance.
        public let photos: Int
        public let mappings: Int
        /// Unique folder, website and contact artwork, including both appearances.
        public let folderCovers: Int
        public let folderCoverPhotos: Int
        /// Contact tiles, including repeated numbers with different operations.
        public let contactItems: Int
        /// Durable action-library records, including unused manual names.
        public let actionLibraryEntries: Int
        /// Archived records within `actionLibraryEntries`.
        public let archivedEntries: Int
        /// Named appearance copies; importing them does not apply them to groups.
        public let appearancePresets: Int

        public init(groups: Int = 0, icons: Int = 0, photos: Int = 0, mappings: Int = 0,
                    folderCovers: Int = 0, folderCoverPhotos: Int = 0, contactItems: Int = 0,
                    actionLibraryEntries: Int = 0, archivedEntries: Int = 0, appearancePresets: Int = 0) {
            self.groups = groups
            self.icons = icons
            self.photos = photos
            self.mappings = mappings
            self.folderCovers = folderCovers
            self.folderCoverPhotos = folderCoverPhotos
            self.contactItems = contactItems
            self.actionLibraryEntries = actionLibraryEntries
            self.archivedEntries = archivedEntries
            self.appearancePresets = appearancePresets
        }
    }

    /// Only decode/export can create a document; every record has been validated.
    public struct Document: Sendable {
        public let createdAt: Date
        public let groups: [SavedGroup]
        let icons: [IconRecord]
        let mappings: [MappingRecord]
        let coverAssets: [CoverAssetRecord]
        let actionLibrary: [ActionLibraryRecord]
        let appearancePresets: [AppearancePreset]

        init(createdAt: Date, groups: [SavedGroup], icons: [IconRecord], mappings: [MappingRecord],
             coverAssets: [CoverAssetRecord] = [], actionLibrary: [ActionLibraryRecord] = [],
             appearancePresets: [AppearancePreset] = []) {
            self.createdAt = createdAt
            self.groups = groups
            self.icons = icons
            self.mappings = mappings
            self.coverAssets = coverAssets
            self.actionLibrary = actionLibrary
            self.appearancePresets = appearancePresets
        }

        public var counts: Counts {
            Counts(groups: groups.count, icons: icons.count,
                   photos: icons.filter { $0.icon.containsPhoto }.count, mappings: mappings.count,
                   folderCovers: coverAssets.count, folderCoverPhotos: coverAssets.filter { $0.icon.kind == .photo }.count,
                   contactItems: groups.reduce(0) { $0 + $1.contactItemCount },
                   actionLibraryEntries: actionLibrary.count, archivedEntries: actionLibrary.filter(\.isArchived).count,
                   appearancePresets: appearancePresets.count)
        }
    }

    /// Preparing a plan is read-only. Its group names and fresh identities are the
    /// exact copies shown in the confirmation UI and later passed to storage.
    public struct ImportPlan: Sendable {
        public let groups: [SavedGroup]
        public let counts: Counts
        public let keptExisting: Counts
        public let isAvailable: Bool
        let icons: [IconRecord]
        let mappings: [MappingRecord]
        // Keep the complete payload, including currently reusable assets. An
        // asset can be collected between the preview and confirmed import.
        let coverAssets: [CoverAssetRecord]
        // Keep the complete metadata payload: even records kept at preview
        // need a fresh conflict/readability check when the user confirms.
        let actionLibrary: [ActionLibraryRecord]
        /// Complete backup candidates, including names kept at preview. The
        /// store decides actual ownership again under its lock during import.
        public let appearancePresets: [AppearancePreset]

        init(groups: [SavedGroup], counts: Counts, keptExisting: Counts, isAvailable: Bool,
             icons: [IconRecord], mappings: [MappingRecord], coverAssets: [CoverAssetRecord],
             actionLibrary: [ActionLibraryRecord], appearancePresets: [AppearancePreset] = []) {
            self.groups = groups
            self.counts = counts
            self.keptExisting = keptExisting
            self.isAvailable = isAvailable
            self.icons = icons
            self.mappings = mappings
            self.coverAssets = coverAssets
            self.actionLibrary = actionLibrary
            self.appearancePresets = appearancePresets
        }
    }

    public enum ImportStatus: Sendable, Equatable {
        case completed
        /// A write failed, and every record attempted by this import is absent.
        case rolledBack
        /// A write failed and at least one attempted record could not be removed.
        case partial
        case unavailable
    }

    public struct ImportResult: Sendable {
        public let status: ImportStatus
        /// Records still present after success or rollback, including unreadable
        /// records that could not be removed. Partial never means all-or-nothing.
        public let imported: Counts
        public let keptExisting: Counts
        public let failedRecords: [String]
        public let groups: [SavedGroup]
    }

    public static var isAvailable: Bool { LiveLibraryBackupStorage().isAvailable }

    public static func exportData() throws -> Data {
        try FolderCoverAssetCoordinator.withLock { try LibraryBackupEngine(storage: LiveLibraryBackupStorage()).exportData() }
    }

    /// Exports the saved group and only its named action artwork, manual matches
    /// and referenced covers and action-library preferences. Unsaved drafts and unrelated library data are not
    /// included. Global appearance presets are not read or included. A missing or
    /// unreadable group fails rather than exporting empty.
    public static func exportData(groupID: UUID) throws -> Data {
        try FolderCoverAssetCoordinator.withLock {
            try LibraryBackupEngine(storage: LiveLibraryBackupStorage()).exportData(groupID: groupID)
        }
    }

    /// The caller owns security-scoped access. Bound both metadata and actual
    /// bytes before parsing, including a file that grows between those checks.
    public static func read(from url: URL) throws -> Document {
        do {
            guard url.isFileURL else { throw LibraryBackupError.readFailed }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize else { throw LibraryBackupError.readFailed }
            guard size <= maximumFileBytes else { throw LibraryBackupError.fileTooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= maximumFileBytes {
                let amount = min(65_536, maximumFileBytes + 1 - data.count)
                guard let next = try handle.read(upToCount: amount), !next.isEmpty else { break }
                data.append(next)
            }
            guard data.count <= maximumFileBytes else { throw LibraryBackupError.fileTooLarge }
            return try decode(data)
        } catch let error as LibraryBackupError { throw error }
        catch { throw LibraryBackupError.readFailed }
    }

    public static func decode(_ data: Data) throws -> Document {
        guard data.count <= maximumFileBytes else { throw LibraryBackupError.fileTooLarge }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw LibraryBackupError.invalidFormat
        }
        guard (1...version).contains(header.version) else {
            throw LibraryBackupError.unsupportedVersion(header.version)
        }
        do {
            let envelope = try decoder.decode(Envelope.self, from: data)
            let document = Document(createdAt: envelope.createdAt, groups: envelope.groups,
                                    icons: envelope.icons, mappings: envelope.mappings, coverAssets: envelope.coverAssets,
                                    actionLibrary: envelope.actionLibrary, appearancePresets: envelope.appearancePresets)
            guard valid(document) else { throw LibraryBackupError.invalidContents }
            return document
        } catch { throw LibraryBackupError.invalidContents }
    }

    public static func prepareImport(_ document: Document, copyNameSuffix: String = " (Copy)") -> ImportPlan {
        FolderCoverAssetCoordinator.withLock {
            LibraryBackupEngine(storage: LiveLibraryBackupStorage()).prepareImport(document, copyNameSuffix: copyNameSuffix)
        }
    }

    public static func apply(_ plan: ImportPlan) -> ImportResult {
        FolderCoverAssetCoordinator.withLock { LibraryBackupEngine(storage: LiveLibraryBackupStorage()).apply(plan) }
    }

    static func encode(_ document: Document) throws -> Data {
        guard valid(document) else { throw LibraryBackupError.invalidContents }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(Envelope(document: document))
            guard data.count <= maximumFileBytes else { throw LibraryBackupError.fileTooLarge }
            return data
        } catch let error as LibraryBackupError { throw error }
        catch { throw LibraryBackupError.exportFailed }
    }

    static func normalizedName(_ name: String) -> String { SavedGroupBinding.normalizedName(name) }

    static func validName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 1_024
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    static func valid(_ document: Document) -> Bool {
        guard document.createdAt.timeIntervalSinceReferenceDate.isFinite,
              document.groups.count <= maximumGroups, document.icons.count <= maximumIcons,
              document.mappings.count <= maximumMappings,
              document.actionLibrary.count <= ActionLibraryRepository.maximumRecords,
              document.appearancePresets.count <= AppearancePresetRepository.maximumRecords,
              Set(document.groups.map(\.id)).count == document.groups.count,
              document.groups.allSatisfy(\.isValid) else { return false }
        var names = Set<String>()
        for record in document.icons {
            guard validName(record.name), names.insert(normalizedName(record.name)).inserted,
                  record.icon.isValid else { return false }
        }
        names.removeAll()
        for record in document.mappings {
            guard validName(record.name), names.insert(normalizedName(record.name)).inserted,
                  record.mapping != nil,
                  record.country == nil || AppStoreCountry.normalized(record.country!) == record.country else { return false }
        }
        names.removeAll()
        for record in document.actionLibrary {
            guard record.isValid,
                  names.insert(normalizedName(record.name)).inserted else { return false }
        }
        names.removeAll()
        for record in document.appearancePresets {
            guard record.isValid, names.insert(record.id).inserted else { return false }
        }
        let referenced = document.groups.reduce(into: Set<FolderCoverAssetID>()) { $0.formUnion($1.coverAssetIDs) }
        var assetIDs = Set<FolderCoverAssetID>()
        for asset in document.coverAssets {
            guard assetIDs.insert(asset.id).inserted,
                  FolderCoverAssetRepository.id(for: asset.icon) == asset.id else { return false }
        }
        guard referenced == assetIDs else { return false }
        return true
    }

    struct IconRecord: Codable, Sendable, Equatable {
        let name: String
        let icon: CustomIconVariants

        init(name: String, icon: CustomIconVariants) {
            self.name = name
            self.icon = icon
        }

        // `icon` is the original standard-image field. Keeping that shape reads
        // old disk records and backups without migration or image re-encoding.
        private enum CodingKeys: String, CodingKey { case name, icon, darkIcon }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            icon = CustomIconVariants(standard: try values.decodeIfPresent(CustomIcon.self, forKey: .icon),
                                      dark: try values.decodeIfPresent(CustomIcon.self, forKey: .darkIcon))
            guard icon.isValid else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Empty custom icon record"))
            }
        }

        func encode(to encoder: any Encoder) throws {
            guard icon.isValid else { throw LibraryBackupError.invalidContents }
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(name, forKey: .name)
            try values.encodeIfPresent(icon.standard, forKey: .icon)
            try values.encodeIfPresent(icon.dark, forKey: .darkIcon)
        }
    }

    struct MappingRecord: Codable, Sendable, Equatable {
        let name: String
        let appStoreID: Int
        let country: String?

        init(name: String, appStoreID: Int, country: String? = nil) {
            self.name = name
            self.appStoreID = appStoreID
            self.country = country
        }

        init(name: String, mapping: DirectLaunchOverrides.Mapping) {
            self.init(name: name, appStoreID: mapping.appStoreID, country: mapping.country)
        }

        var mapping: DirectLaunchOverrides.Mapping? {
            DirectLaunchOverrides.Mapping(appStoreID: appStoreID, country: country)
        }
    }

    struct CoverAssetRecord: Codable, Sendable, Equatable {
        let id: FolderCoverAssetID
        let icon: CustomIcon
    }

    private struct Header: Decodable { let format: String; let version: Int }

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let createdAt: Date
        let groups: [SavedGroup]
        let icons: [IconRecord]
        let mappings: [MappingRecord]
        let coverAssets: [CoverAssetRecord]
        let actionLibrary: [ActionLibraryRecord]
        let appearancePresets: [AppearancePreset]

        init(document: Document) {
            format = LibraryBackup.format
            version = LibraryBackup.version
            createdAt = document.createdAt
            groups = document.groups
            icons = document.icons
            mappings = document.mappings
            coverAssets = document.coverAssets
            actionLibrary = document.actionLibrary
            appearancePresets = document.appearancePresets
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case format, version, createdAt, groups, icons, mappings, coverAssets, actionLibrary, appearancePresets }
        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(from decoder: any Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
            let values = try decoder.container(keyedBy: CodingKeys.self)
            format = try values.decode(String.self, forKey: .format)
            version = try values.decode(Int.self, forKey: .version)
            var expectedKeys = Set(CodingKeys.allCases.map(\.rawValue))
            if version < 5 { expectedKeys.remove(CodingKeys.coverAssets.rawValue) }
            if version < 12 { expectedKeys.remove(CodingKeys.actionLibrary.rawValue) }
            if version < 15 { expectedKeys.remove(CodingKeys.appearancePresets.rawValue) }
            guard Set(keys) == expectedKeys else { throw LibraryBackupError.invalidContents }
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            groups = try Self.groups(values, version: version)
            guard version >= 6 || !groups.contains(where: { Self.containsWebsite($0.items) }) else {
                throw LibraryBackupError.invalidContents
            }
            icons = try Self.array(values, key: .icons, limit: maximumIcons)
            mappings = try Self.mappings(values, version: version)
            if version >= 5 {
                let referenced = groups.reduce(into: Set<FolderCoverAssetID>()) { $0.formUnion($1.coverAssetIDs) }
                coverAssets = try Self.array(values, key: .coverAssets, limit: referenced.count)
            } else {
                coverAssets = []
            }
            actionLibrary = version >= 12
                ? try Self.array(values, key: .actionLibrary, limit: ActionLibraryRepository.maximumRecords) : []
            appearancePresets = version >= 15
                ? try Self.appearancePresets(values, version: version) : []
            // Date artwork can live in either action appearance or any shared
            // node asset. Older envelopes must not smuggle the new icon kind.
            guard version >= 11 || (!icons.contains { $0.icon.containsDate }
                                    && !coverAssets.contains { $0.icon.kind == .date }) else {
                throw LibraryBackupError.invalidContents
            }
        }

        private static func containsWebsite(_ items: [GroupItem]) -> Bool {
            items.contains { $0.kind == .website || containsWebsite($0.children) }
        }

        private static func mappings(_ values: KeyedDecodingContainer<CodingKeys>, version: Int) throws -> [MappingRecord] {
            var container = try values.nestedUnkeyedContainer(forKey: .mappings)
            guard let count = container.count, count <= maximumMappings else { throw LibraryBackupError.invalidContents }
            var records: [MappingRecord] = []
            records.reserveCapacity(count)
            while !container.isAtEnd {
                let decoder = try container.superDecoder()
                let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
                guard keys.isSubset(of: ["name", "appStoreID", "country"]),
                      version >= 10 || !keys.contains("country") else { throw LibraryBackupError.invalidContents }
                records.append(try MappingRecord(from: decoder))
            }
            return records
        }

        private enum GroupKeys: String, CodingKey { case appearance, items }
        private enum ItemKeys: String, CodingKey { case kind, children, websiteBrowser, folderAppearance }
        private enum PresetKeys: String, CodingKey { case appearance }

        private static func groups(_ values: KeyedDecodingContainer<CodingKeys>, version: Int) throws -> [SavedGroup] {
            var container = try values.nestedUnkeyedContainer(forKey: .groups)
            guard let count = container.count, count <= maximumGroups else { throw LibraryBackupError.invalidContents }
            var groups: [SavedGroup] = []
            groups.reserveCapacity(count)
            while !container.isAtEnd {
                let decoder = try container.superDecoder()
                if version < 16 {
                    let group = try decoder.container(keyedBy: GroupKeys.self)
                    if group.contains(.appearance), try !group.decodeNil(forKey: .appearance) {
                        try rejectNewerAppearanceFields(in: group.superDecoder(forKey: .appearance), version: version)
                    }
                    var budget = SavedGroup.maximumItems
                    var items = try group.nestedUnkeyedContainer(forKey: .items)
                    try rejectNewerItemFields(in: &items, version: version, depth: 0, budget: &budget)
                }
                groups.append(try SavedGroup(from: decoder))
            }
            return groups
        }

        /// Inspect every node before the model can decode missing/null optional
        /// fields as nil. Older envelopes cannot hide fields from a newer schema.
        private static func rejectNewerItemFields(in items: inout UnkeyedDecodingContainer,
                                                 version: Int, depth: Int, budget: inout Int) throws {
            guard depth <= SavedGroup.maximumDepth else { throw LibraryBackupError.invalidContents }
            while !items.isAtEnd {
                guard budget > 0 else { throw LibraryBackupError.invalidContents }
                budget -= 1
                let decoder = try items.superDecoder()
                let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
                guard version >= 8 || keys.isDisjoint(with: ["folderAppearance", "folderPreviewGrid"]),
                      version >= 9 || keys.isDisjoint(with: ["contactTarget", "contactIcon"]),
                      version >= 13 || !keys.contains("websiteBrowser") else {
                    throw LibraryBackupError.invalidContents
                }
                let node = try decoder.container(keyedBy: ItemKeys.self)
                if node.contains(.folderAppearance), try !node.decodeNil(forKey: .folderAppearance) {
                    try rejectNewerAppearanceFields(in: node.superDecoder(forKey: .folderAppearance), version: version)
                }
                // Freeze v13's four browser names even when the current enum
                // grows. Null and missing remain its original system default.
                if version == 13, let browser = try node.decodeIfPresent(String.self, forKey: .websiteBrowser),
                   !["systemDefault", "inAppSafari", "chrome", "firefox"].contains(browser) {
                    throw LibraryBackupError.invalidContents
                }
                if version < 9, try node.decode(String.self, forKey: .kind) == "contact" {
                    throw LibraryBackupError.invalidContents
                }
                var children = try node.nestedUnkeyedContainer(forKey: .children)
                // Leaves at the fourth folder level have an empty children
                // array; do not count that empty array as a fifth folder.
                if !children.isAtEnd {
                    try rejectNewerItemFields(in: &children, version: version, depth: depth + 1, budget: &budget)
                }
            }
        }

        /// All appearance locations share the same version boundary. Inspect
        /// raw keys before optional decoding can erase explicit null/defaults.
        private static func rejectNewerAppearanceFields(in decoder: any Decoder, version: Int) throws {
            let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
            guard version >= 8 || !keys.contains("backButtonStyle"),
                  version >= 7 || !keys.contains("density"),
                  version >= 16 || keys.isDisjoint(with: ["spacing", "margin", "titleColorHex", "titleOutlineHex", "titleOutlineWidth"]) else {
                throw LibraryBackupError.invalidContents
            }
        }

        private static func appearancePresets(_ values: KeyedDecodingContainer<CodingKeys>, version: Int) throws -> [AppearancePreset] {
            var container = try values.nestedUnkeyedContainer(forKey: .appearancePresets)
            guard let count = container.count, count <= AppearancePresetRepository.maximumRecords else {
                throw LibraryBackupError.invalidContents
            }
            var result: [AppearancePreset] = []
            result.reserveCapacity(count)
            while !container.isAtEnd {
                let decoder = try container.superDecoder()
                if version < 16 {
                    let preset = try decoder.container(keyedBy: PresetKeys.self)
                    try rejectNewerAppearanceFields(in: preset.superDecoder(forKey: .appearance), version: version)
                }
                result.append(try AppearancePreset(from: decoder))
            }
            return result
        }

        private static func array<T: Decodable>(_ values: KeyedDecodingContainer<CodingKeys>, key: CodingKeys, limit: Int) throws -> [T] {
            var container = try values.nestedUnkeyedContainer(forKey: key)
            guard let count = container.count, count <= limit else { throw LibraryBackupError.invalidContents }
            var result: [T] = []
            result.reserveCapacity(count)
            while !container.isAtEnd { result.append(try container.decode(T.self)) }
            return result
        }
    }
}
