import Foundation

/// A contact entry point contains identities only. The current saved node, not
/// a URL argument, supplies both the number and the requested operation.
public struct ContactLaunchRoute: Sendable, Equatable {
    public let groupID: UUID
    public let itemID: UUID
    private static let prefix = "appfolder://contact?"

    public init(groupID: UUID, itemID: UUID) {
        self.groupID = groupID
        self.itemID = itemID
    }

    public var url: URL {
        URL(string: Self.prefix + "group=\(groupID.uuidString.lowercased())&item=\(itemID.uuidString.lowercased())")!
    }

    public init?(url: URL) {
        let raw = url.absoluteString
        guard url.baseURL == nil, raw.utf8.count <= 256, raw.hasPrefix(Self.prefix) else { return nil }
        let fields = raw.dropFirst(Self.prefix.count).split(separator: "&", omittingEmptySubsequences: false)
        guard fields.count == 2 else { return nil }
        var values: [String: String] = [:]
        for field in fields {
            let pair = field.split(separator: "=", omittingEmptySubsequences: false)
            guard pair.count == 2, ["group", "item"].contains(String(pair[0])), values[String(pair[0])] == nil else { return nil }
            values[String(pair[0])] = String(pair[1])
        }
        guard let group = values["group"], let item = values["item"],
              let groupID = UUID(uuidString: group), let itemID = UUID(uuidString: item),
              group == groupID.uuidString.lowercased(), item == itemID.uuidString.lowercased() else { return nil }
        self.init(groupID: groupID, itemID: itemID)
    }

    /// A moved contact still resolves; deletion, type changes, or an invalid
    /// group never fall back to a contact with a similar name or number.
    public func resolve(in group: SavedGroup) -> GroupItem? {
        LockScreenItemChoice.resolve(.init(groupID: groupID, itemID: itemID), in: group,
                                     expectedKind: .contact)?.item
    }
}
