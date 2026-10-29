import Foundation

/// User organization of an action's binding name, never a system action token.
/// A record with no tags is still a durable, manually saved candidate name.
public struct ActionLibraryRecord: Codable, Sendable, Equatable, Identifiable {
    public static let maximumTags = 16
    public static let maximumTagLength = 32
    public static let maximumTagUTF8Bytes = 128

    public let name: String
    public let tags: [String]
    public let isArchived: Bool
    public var id: String { SavedGroupBinding.normalizedName(name) }

    public init?(name: String, tags: [String] = [], isArchived: Bool = false) {
        guard Self.isValidName(name), Self.isValidName(Self.normalizedText(name)),
              tags.count <= Self.maximumTags else { return nil }
        var unique: [String: String] = [:]
        for tag in tags {
            guard Self.isValidTag(tag), Self.isValidTag(Self.normalizedText(tag)) else { return nil }
            let value = Self.normalizedText(tag)
            let key = SavedGroupBinding.normalizedName(value)
            if unique[key] == nil { unique[key] = value }
        }
        self.name = Self.normalizedText(name)
        self.tags = unique.keys.sorted().compactMap { unique[$0] }
        self.isArchived = isArchived
    }

    public var isValid: Bool {
        Self(name: name, tags: tags, isArchived: isArchived) == self
    }

    /// This is the same length/control-character boundary as an action leaf.
    /// Search may fold accents or width; identity deliberately does neither.
    public static func isValidName(_ name: String) -> Bool {
        validText(name, maximumLength: SavedGroup.maximumNameLength, maximumBytes: 512)
    }

    public static func isValidTag(_ tag: String) -> Bool {
        validText(tag, maximumLength: maximumTagLength, maximumBytes: maximumTagUTF8Bytes)
    }

    private static func validText(_ input: String, maximumLength: Int, maximumBytes: Int) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumLength && trimmed.utf8.count <= maximumBytes
            && !input.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func normalizedText(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case name, tags, isArchived }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let keys = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        guard keys == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid action library fields"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let name = try values.decode(String.self, forKey: .name)
        var tags = try values.nestedUnkeyedContainer(forKey: .tags)
        var decodedTags: [String] = []
        while !tags.isAtEnd {
            guard decodedTags.count < Self.maximumTags else {
                throw DecodingError.dataCorruptedError(in: tags, debugDescription: "Too many action tags")
            }
            decodedTags.append(try tags.decode(String.self))
        }
        let archived = try values.decode(Bool.self, forKey: .isArchived)
        guard let record = Self(name: name, tags: decodedTags, isArchived: archived),
              record.name.utf8.elementsEqual(name.utf8), record.tags.count == decodedTags.count,
              Set(decodedTags.map(SavedGroupBinding.normalizedName)).count == decodedTags.count,
              decodedTags.allSatisfy({ Self.normalizedText($0).utf8.elementsEqual($0.utf8) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid action library record"))
        }
        self = record
    }
}

/// Compare-and-set one name; nil expected means it must still be absent.
/// Nil replacement removes organization only, not nodes, artwork or mappings.
public struct ActionLibraryMutation: Sendable, Equatable {
    public let name: String
    public let expected: ActionLibraryRecord?
    public let replacement: ActionLibraryRecord?

    public init(name: String, expected: ActionLibraryRecord?, replacement: ActionLibraryRecord?) {
        self.name = name
        self.expected = expected
        self.replacement = replacement
    }
}

public enum ActionLibraryError: Error, Sendable, Equatable {
    case unavailable
    case busy
    case unreadable
    case invalidChanges
    case capacityExceeded
    case conflict([String])
    /// The requested bytes could not be confirmed. Reload before retrying.
    case writeFailed
}

public struct ActionLibrarySnapshot: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case available, unavailable, busy, unreadable }
    public let records: [ActionLibraryRecord]
    public let status: Status

    public init(records: [ActionLibraryRecord] = [], status: Status) {
        self.records = records
        self.status = status
    }
}

/// Receipt ownership is established under the exclusive file lock before any
/// write. Even an unconfirmed write returns its attempted names to the importer.
public struct ActionLibraryInsertResult: Sendable, Equatable {
    public let didCommit: Bool
    public let attemptedRecords: [ActionLibraryRecord]
    public let keptExistingRecords: [ActionLibraryRecord]
    public let error: ActionLibraryError?

    public init(didCommit: Bool, attemptedRecords: [ActionLibraryRecord] = [],
                keptExistingRecords: [ActionLibraryRecord] = [], error: ActionLibraryError? = nil) {
        self.didCommit = didCommit
        self.attemptedRecords = attemptedRecords
        self.keptExistingRecords = keptExistingRecords
        self.error = error
    }
}

public struct ActionLibraryRollbackResult: Sendable, Equatable {
    /// Names that still exist, including records changed by another editor.
    public let remainingNames: Set<String>
    public init(remainingNames: Set<String>) { self.remainingNames = remainingNames }
}
