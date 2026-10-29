import Foundation

/// Carries saved identities only. The current node supplies both the website
/// URL and browser; a caller cannot inject either into this host entry point.
public struct WebsiteLaunchRoute: Sendable, Equatable {
    public let groupID: UUID
    public let itemID: UUID
    private static let prefix = "appfolder://website?"

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

    /// Moving a node retains its identity. Deleted, replaced or invalid nodes
    /// never fall back to a similarly named website or a previous URL.
    public func resolve(in group: SavedGroup) -> GroupItem? {
        LockScreenItemChoice.resolve(.init(groupID: groupID, itemID: itemID), in: group,
                                     expectedKind: .website)?.item
    }
}
