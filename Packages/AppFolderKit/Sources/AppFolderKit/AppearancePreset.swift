import Foundation

/// A named copy of the existing appearance value. Applying a preset never
/// binds a group to later preset edits or changes any global appearance.
public struct AppearancePreset: Codable, Identifiable, Sendable, Equatable {
    public static let maximumNameLength = 64
    public static let maximumNameUTF8Bytes = 256

    public let name: String
    public let appearance: SavedGroupAppearance
    public var id: String { SavedGroupBinding.normalizedName(name) }

    /// Valid spelling variations have one stored form. Invalid drafts remain
    /// invalid, including controls trimmed away by whitespace normalization.
    public init(name: String, appearance: SavedGroupAppearance) {
        self.name = Self.isValidName(name) ? Self.normalizedText(name) : name
        self.appearance = appearance.normalized
    }

    public var isValid: Bool {
        Self.isValidName(name)
            && Self.normalizedText(name).utf8.elementsEqual(name.utf8)
            && appearance.isValid
    }

    public static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedText(name)
        return !trimmed.isEmpty && trimmed.count <= maximumNameLength
            && trimmed.utf8.count <= maximumNameUTF8Bytes
            && normalized.count <= maximumNameLength && normalized.utf8.count <= maximumNameUTF8Bytes
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func normalizedText(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case name, appearance }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        guard keys == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "Invalid appearance preset fields"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let name = try values.decode(String.self, forKey: .name)
        let appearance = try values.decode(SavedGroupAppearance.self, forKey: .appearance)
        let record = Self(name: name, appearance: appearance)
        guard record.isValid, record.name.utf8.elementsEqual(name.utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "Invalid appearance preset"))
        }
        self = record
    }

    public func encode(to encoder: any Encoder) throws {
        guard isValid else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                        debugDescription: "Invalid appearance preset"))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(appearance, forKey: .appearance)
    }
}

/// Compare-and-set one normalized name. A rename to a different id is a
/// deletion and insertion in the same batch; nil expected means still absent.
public struct AppearancePresetMutation: Sendable, Equatable {
    public let name: String
    public let expected: AppearancePreset?
    public let replacement: AppearancePreset?

    public init(name: String, expected: AppearancePreset?, replacement: AppearancePreset?) {
        self.name = name
        self.expected = expected
        self.replacement = replacement
    }
}

public enum AppearancePresetError: Error, Sendable, Equatable {
    case unavailable
    case busy
    case unreadable
    case invalidChanges
    case capacityExceeded
    case conflict([String])
    /// The requested bytes could not be confirmed. Reload before retrying.
    case writeFailed
}

public struct AppearancePresetSnapshot: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case available, unavailable, busy, unreadable }
    public let records: [AppearancePreset]
    public let status: Status

    public init(records: [AppearancePreset] = [], status: Status) {
        self.records = records
        self.status = status
    }
}

/// Only rows absent under the write lock belong to this import. An unconfirmed
/// write still retains its attempted rows for a later conditional rollback.
public struct AppearancePresetInsertResult: Sendable, Equatable {
    public let didCommit: Bool
    public let attemptedRecords: [AppearancePreset]
    public let keptExistingRecords: [AppearancePreset]
    public let error: AppearancePresetError?

    public init(didCommit: Bool, attemptedRecords: [AppearancePreset] = [],
                keptExistingRecords: [AppearancePreset] = [], error: AppearancePresetError? = nil) {
        self.didCommit = didCommit
        self.attemptedRecords = attemptedRecords
        self.keptExistingRecords = keptExistingRecords
        self.error = error
    }
}

public struct AppearancePresetRollbackResult: Sendable, Equatable {
    /// Normalized names that remain, including a later edit by another writer.
    public let remainingNames: Set<String>
    public init(remainingNames: Set<String>) { self.remainingNames = remainingNames }
}
