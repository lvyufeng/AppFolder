import Foundation

/// Pure draft editing. This never saves a group or consumes the inbox; callers
/// keep their existing save/cancel/history flow and acknowledge only after save.
public enum ShareInboxImport {
    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidGroup, invalidPath, invalidFallbackName, identityConflict, invalidEntries, capacityExceeded
    }

    public struct Result: Sendable, Equatable {
        public let nextGroup: SavedGroup
        /// Includes already-present websites, for a prior successful save whose
        /// inbox removal failed. An edited existing website is never overwritten.
        public let selectedIDs: Set<UUID>
        public let addedCount: Int
    }

    public static func apply(entries: [ShareInboxEntry], to group: SavedGroup,
                             path: [UUID] = [], fallbackName: String) throws -> Result {
        guard group.isValid else { throw Error.invalidGroup }
        guard var items = group.items(at: path) else { throw Error.invalidPath }
        guard entries.count <= ShareInboxStore.maximumEntries else { throw Error.invalidEntries }
        let existing = allItems(in: group)
        var selected: [UUID: ShareInboxEntry] = [:]
        var additions: [GroupItem] = []
        for entry in entries {
            if let prior = selected[entry.id] {
                guard prior == entry else { throw Error.identityConflict }
                continue
            }
            selected[entry.id] = entry
            if let present = existing[entry.itemID] {
                guard present.kind == .website else { throw Error.identityConflict }
                continue
            }
            let name = try title(for: entry, fallbackName: fallbackName)
            additions.append(GroupItem(id: entry.itemID, kind: .website, name: name, websiteURL: entry.url))
        }
        guard existing.count + additions.count <= SavedGroup.maximumItems else { throw Error.capacityExceeded }
        items.append(contentsOf: additions)
        var next = group
        guard next.replaceItems(items, at: path) else { throw Error.invalidEntries }
        return .init(nextGroup: next, selectedIDs: Set(selected.keys), addedCount: additions.count)
    }

    /// A manual title is never truncated. With no title, use a legal host label
    /// or the caller's localized fallback, without fetching remote metadata.
    public static func title(for entry: ShareInboxEntry, fallbackName: String) throws -> String {
        if let title = entry.title { return title }
        if let host = WebsiteURL.validated(entry.url)?.host(percentEncoded: false),
           let title = try? ShareInboxEntry.normalizedTitle(host) { return title }
        guard let fallback = try? ShareInboxEntry.normalizedTitle(fallbackName) else {
            throw Error.invalidFallbackName
        }
        return fallback
    }

    /// Only a successfully persisted final tree may be supplied here. Undoing or
    /// deleting a selected website removes its ID from this acknowledgement set.
    public static func consumableIDs(selectedIDs: Set<UUID>, in savedGroup: SavedGroup) -> Set<UUID> {
        guard savedGroup.isValid else { return [] }
        return Set(allItems(in: savedGroup).values.lazy.filter { $0.kind == .website && selectedIDs.contains($0.id) }.map(\.id))
    }

    private static func allItems(in group: SavedGroup) -> [UUID: GroupItem] {
        var result: [UUID: GroupItem] = [:]
        var pending = group.items
        while let item = pending.popLast() {
            result[item.id] = item
            pending.append(contentsOf: item.children)
        }
        return result
    }
}
