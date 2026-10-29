import Foundation

public enum ShareInboxError: Error, Sendable, Equatable {
    case unavailable
    case invalidURL
    case invalidTitle
    case full
    case busy
    case storageFailure
    case recordTooLarge
    case recordAlreadyExists
}

/// One explicitly submitted website. Its identity survives reloads and can be
/// reused as the imported website node's ID to detect a repeated import.
public struct ShareInboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: String
    public let title: String?
    public let createdAt: Date
    public var itemID: UUID { id }

    init(id: UUID, url: String, title: String?, createdAt: Date) throws {
        guard let validated = WebsiteURL.validated(url) else { throw ShareInboxError.invalidURL }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else { throw ShareInboxError.storageFailure }
        self.id = id
        self.url = validated.absoluteString
        self.title = try Self.normalizedTitle(title)
        self.createdAt = createdAt
    }

    static func normalizedTitle(_ title: String?) throws -> String? {
        guard let title else { return nil }
        // Check raw bytes before trimming, without locale-dependent folding.
        guard title.utf8.count <= ShareInboxStore.maximumTitleUTF8Bytes,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ShareInboxError.invalidTitle
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= ShareInboxStore.maximumTitleCharacters else { throw ShareInboxError.invalidTitle }
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case version, id, url, title, createdAt }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
        guard Set(keys).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown inbox field"))
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported inbox version")
        }
        let url = try values.decode(String.self, forKey: .url)
        let title = try values.decodeIfPresent(String.self, forKey: .title)
        try self.init(id: values.decode(UUID.self, forKey: .id), url: url, title: title,
                      createdAt: values.decode(Date.self, forKey: .createdAt))
        guard self.url == url, self.title == title else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Noncanonical inbox record"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .version)
        try values.encode(id, forKey: .id)
        try values.encode(url, forKey: .url)
        try values.encodeIfPresent(title, forKey: .title)
        try values.encode(createdAt, forKey: .createdAt)
    }
}

public struct ShareInboxSnapshot: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case available, unavailable, busy, directoryFailure, overCapacity
    }

    public let entries: [ShareInboxEntry]
    /// Bad or unreadable records remain on disk and still occupy queue capacity.
    public let unreadableCount: Int
    public let recordCount: Int
    public let status: Status

    public init(entries: [ShareInboxEntry], unreadableCount: Int, recordCount: Int, status: Status) {
        self.entries = entries
        self.unreadableCount = unreadableCount
        self.recordCount = recordCount
        self.status = status
    }

    public var isAvailable: Bool { status != .unavailable }
    public var hasReadFailures: Bool { status != .available || unreadableCount > 0 }
    public var isEmpty: Bool { status == .available && recordCount == 0 }
}

/// Injectable for consumers that must test save-then-remove ordering. A snapshot
/// whose status is not .available must not replace the previously displayed list.
public protocol ShareInboxStorage: Sendable {
    var snapshot: ShareInboxSnapshot { get }
    func enqueue(url: String, title: String?) throws -> ShareInboxEntry
    /// Call only after the destination group save succeeds. False means this ID
    /// was already absent. Never remove pending entries merely because read or
    /// destination-save failed; retain itemID in the saved node for retry checks.
    @discardableResult func remove(id: UUID) throws -> Bool
}

public enum ShareInboxStore {
    public static let maximumEntries = 100
    public static let maximumRecordBytes = 8 * 1_024
    public static let maximumTitleCharacters = 80
    public static let maximumTitleUTF8Bytes = 512

    private static let repository: ShareInboxRepository = {
        #if os(iOS)
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier
        )
        return ShareInboxRepository(directory: container?.appendingPathComponent("WebShareInbox", isDirectory: true))
        #else
        return ShareInboxRepository(directory: nil)
        #endif
    }()

    public static var storage: any ShareInboxStorage { repository }
    public static var snapshot: ShareInboxSnapshot { repository.snapshot }
    public static func enqueue(url: String, title: String? = nil) throws -> ShareInboxEntry {
        try repository.enqueue(url: url, title: title)
    }
    @discardableResult
    public static func remove(id: UUID) throws -> Bool { try repository.remove(id: id) }

    /// Remove only this exact snapshot. Offer undo only when this returns true;
    /// an absent entry returns false, while a changed or unreadable entry fails.
    @discardableResult
    public static func remove(ifMatching entry: ShareInboxEntry) throws -> Bool {
        try repository.remove(ifMatching: entry)
    }

    /// Undo a removal without changing identity, content or creation time. An
    /// identical existing entry succeeds; a different record is never replaced.
    public static func restore(_ entry: ShareInboxEntry) throws {
        try repository.restore(entry)
    }
}
