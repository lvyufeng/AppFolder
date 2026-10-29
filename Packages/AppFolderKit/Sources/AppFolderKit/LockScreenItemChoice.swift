import Foundation

/// A saved group and one of its leaf nodes, independent of names or position.
public struct LockScreenItemID: RawRepresentable, Codable, Hashable, Sendable {
    public let groupID: UUID
    public let itemID: UUID

    public init(groupID: UUID, itemID: UUID) {
        self.groupID = groupID
        self.itemID = itemID
    }

    public var rawValue: String { groupID.uuidString.lowercased() + "/" + itemID.uuidString.lowercased() }

    /// Only the canonical lowercase, hyphenated UUID pair is accepted. No URL
    /// decoding, whitespace repair, alternate UUID forms or extra path segments.
    public init?(rawValue: String) {
        guard rawValue.utf8.count == 73 else { return nil }
        let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.utf8.count == 36 }),
              let group = UUID(uuidString: String(parts[0])),
              let item = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(groupID: group, itemID: item)
        guard self.rawValue == rawValue else { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        guard let id = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid lock screen item ID"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Display metadata plus the exact current leaf. Action titles use their alias,
/// while item.name remains the system-action binding and custom-icon key.
public struct LockScreenItemChoice: Identifiable, Sendable, Equatable {
    public let id: LockScreenItemID
    public let title: String
    public let groupName: String
    public let folderPath: [String]
    public let item: GroupItem

    /// Depth-first display order, including websites and contacts, with no folder or spacer
    /// choices. Validation bounds traversal to the existing four-level tree.
    public static func choices(in group: SavedGroup) -> [Self] {
        guard group.isValid else { return [] }
        var result: [Self] = []
        func visit(_ items: [GroupItem], path: [String]) {
            for item in items {
                switch item.kind {
                case .action, .website, .contact:
                    result.append(.init(id: .init(groupID: group.id, itemID: item.id),
                                        title: item.displayTitle, groupName: group.name,
                                        folderPath: path, item: item))
                case .folder:
                    visit(item.children, path: path + [item.name])
                case .spacer:
                    break
                }
            }
        }
        visit(group.items, path: [])
        return result
    }

    /// Preserves the caller's group order. Duplicated group identities are
    /// ambiguous and excluded, rather than producing duplicate choice IDs.
    public static func choices(in groups: [SavedGroup]) -> [Self] {
        let counts = Dictionary(grouping: groups, by: \.id).mapValues(\.count)
        return groups.flatMap { counts[$0.id] == 1 ? choices(in: $0) : [] }
    }

    /// A moved node remains valid. A missing or non-leaf node has no fallback.
    /// Pass the previously selected kind when changing a leaf's kind must
    /// invalidate the old selection: a UUID pair alone has no historic type.
    public static func resolve(_ id: LockScreenItemID, in group: SavedGroup,
                               expectedKind: GroupItem.Kind? = nil) -> Self? {
        guard group.id == id.groupID,
              let choice = choices(in: group).first(where: { $0.id == id }),
              expectedKind == nil || choice.item.kind == expectedKind else { return nil }
        return choice
    }

    public static func resolve(_ id: LockScreenItemID, in groups: [SavedGroup],
                               expectedKind: GroupItem.Kind? = nil) -> Self? {
        let matching = groups.filter { $0.id == id.groupID }
        guard matching.count == 1, let group = matching.first else { return nil }
        return resolve(id, in: group, expectedKind: expectedKind)
    }
}
