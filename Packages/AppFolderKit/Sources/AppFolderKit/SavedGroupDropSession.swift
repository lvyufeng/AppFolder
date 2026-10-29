import Foundation

/// A drag carries identities and an expected snapshot, never copied content,
/// image bytes, website addresses or contact details.
public struct SavedGroupDropSource: Hashable, Codable, Sendable {
    public let sessionID: UUID
    public let groupID: UUID
    public let itemID: UUID
    public let revision: String

    public init(sessionID: UUID, groupID: UUID, itemID: UUID, revision: String) {
        self.sessionID = sessionID
        self.groupID = groupID
        self.itemID = itemID
        self.revision = revision
    }
}

/// One editor's drag epoch. Generate sources while rendering, but begin only
/// when a real drag starts. Cancelling also invalidates not-yet-begun sources.
public struct SavedGroupDropSession: Sendable {
    private var epoch = UUID()
    public private(set) var activeSource: SavedGroupDropSource?

    public init() {}

    public func source(groupID: UUID, itemID: UUID, revision: String) -> SavedGroupDropSource {
        .init(sessionID: epoch, groupID: groupID, itemID: itemID, revision: revision)
    }

    @discardableResult
    public mutating func begin(_ source: SavedGroupDropSource) -> Bool {
        guard source.sessionID == epoch, activeSource == nil || activeSource == source else { return false }
        activeSource = source
        return true
    }

    /// Consumes synchronously before returning the model operation, including
    /// when that operation later fails. Duplicate callbacks cannot apply twice.
    public mutating func consume(_ source: SavedGroupDropSource, target: SavedGroupDropTarget) -> SavedGroupDropRequest? {
        guard source.sessionID == epoch, activeSource == source else { return nil }
        cancel()
        return .init(groupID: source.groupID, itemID: source.itemID, expectedRevision: source.revision, target: target)
    }

    public mutating func cancel() {
        activeSource = nil
        epoch = UUID()
    }
}
