import CryptoKit
import Foundation

/// An editable layout. Action leaves name an action owned by the system widget
/// configuration; website and contact leaves store their own explicit target.
public struct GroupItem: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case action, website, contact, folder, spacer
    }

    public var id: UUID
    public var kind: Kind
    /// The real system action name for actions, or the title for other kinds.
    /// Action aliases never change the binding or action-icon lookup identity.
    public var name: String
    public var children: [GroupItem]
    /// Optional title for a system action tile; other kinds cannot have aliases.
    public var displayName: String?
    /// Immutable artwork references. Only folders may carry a cover; nil keeps
    /// the content miniature. Photos never become part of a layout snapshot.
    public var folderCover: FolderCover?
    /// A validated absolute HTTP(S) address. Only website leaves may carry it.
    public var websiteURL: String?
    /// Website artwork belongs to this node, never to an action-name icon key.
    public var websiteIcon: FolderCover?
    /// Nil retains the original system-default browser behavior.
    public var websiteBrowser: WebsiteBrowser?
    /// A complete page style for this folder. Nil inherits the closest ancestor.
    public var folderAppearance: SavedGroupAppearance?
    /// Only the node's content miniature; nil keeps the four-leaf preview.
    public var folderPreviewGrid: FolderPreviewGrid?
    /// A chosen single phone number and operation, independent of system actions.
    public var contactTarget: ContactTarget?
    /// Contact artwork belongs to this node, never to a name-based action icon.
    public var contactIcon: FolderCover?

    public init(id: UUID = UUID(), kind: Kind, name: String = "", children: [GroupItem] = [], displayName: String? = nil,
                folderCover: FolderCover? = nil, websiteURL: String? = nil, websiteIcon: FolderCover? = nil,
                folderAppearance: SavedGroupAppearance? = nil, folderPreviewGrid: FolderPreviewGrid? = nil,
                contactTarget: ContactTarget? = nil, contactIcon: FolderCover? = nil,
                websiteBrowser: WebsiteBrowser? = nil) {
        self.id = id
        self.kind = kind
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.children = children
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.folderCover = folderCover
        self.websiteURL = websiteURL
        self.websiteIcon = websiteIcon
        self.websiteBrowser = websiteBrowser
        self.folderAppearance = folderAppearance
        self.folderPreviewGrid = folderPreviewGrid
        self.contactTarget = contactTarget
        self.contactIcon = contactIcon
    }

    public static func action(name: String, displayName: String? = nil) -> GroupItem {
        .init(kind: .action, name: name, displayName: displayName)
    }
    public static func folder(name: String, children: [GroupItem] = [], folderCover: FolderCover? = nil,
                              folderAppearance: SavedGroupAppearance? = nil, folderPreviewGrid: FolderPreviewGrid? = nil) -> GroupItem {
        .init(kind: .folder, name: name, children: children, folderCover: folderCover,
              folderAppearance: folderAppearance, folderPreviewGrid: folderPreviewGrid)
    }
    /// Normalize user input with WebsiteURL before constructing a website draft.
    public static func website(name: String, url: String, icon: FolderCover? = nil, browser: WebsiteBrowser? = nil) -> GroupItem {
        .init(kind: .website, name: name, websiteURL: url, websiteIcon: icon, websiteBrowser: browser)
    }
    public static func contact(name: String, target: ContactTarget, icon: FolderCover? = nil) -> GroupItem {
        .init(kind: .contact, name: name, contactTarget: target, contactIcon: icon)
    }
    public static func spacer() -> GroupItem { .init(kind: .spacer) }

    public var displayTitle: String { kind == .action ? displayName ?? name : name }
    public var effectiveWebsiteBrowser: WebsiteBrowser { websiteBrowser ?? .systemDefault }

    public var artworkReference: FolderCover? {
        switch kind {
        case .folder: folderCover
        case .website: websiteIcon
        case .contact: contactIcon
        case .action, .spacer: nil
        }
    }

    /// The first four descendant actions in depth-first display order. Repeated
    /// names remain repeated tiles. Website/contact leaves do not change this lookup.
    public var previewActionNames: [String] {
        previewItems(includingOtherLeaves: false, limit: 4).map(\.name)
    }

    /// The first four or nine action, website or contact leaves, preserving their node artwork
    /// identity and depth-first order. Empty cells and folders are not leaves.
    public var previewLeafItems: [GroupItem] {
        previewItems(includingOtherLeaves: true, limit: (folderPreviewGrid ?? .four).capacity)
    }

    private func previewItems(includingOtherLeaves: Bool, limit: Int) -> [GroupItem] {
        if kind == .action || (includingOtherLeaves && (kind == .website || kind == .contact)) { return [self] }
        guard kind == .folder else { return [] }
        var leaves: [GroupItem] = []
        // This folder counts toward both limits. Its fourth folder level can
        // contain actions, matching SavedGroup's validation of saved trees.
        var visited = 1
        func visit(_ nodes: [GroupItem], folderDepth: Int) {
            for node in nodes {
                guard leaves.count < limit, visited < SavedGroup.maximumItems else { return }
                visited += 1
                if node.kind == .action || (includingOtherLeaves && (node.kind == .website || node.kind == .contact)) { leaves.append(node) }
                else if node.kind == .folder, folderDepth < SavedGroup.maximumDepth {
                    visit(node.children, folderDepth: folderDepth + 1)
                }
            }
        }
        visit(children, folderDepth: 1)
        return leaves
    }

    fileprivate var normalized: GroupItem {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.folderAppearance = folderAppearance?.normalized
        copy.children = children.map(\.normalized)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, children, displayName, folderCover, websiteURL, websiteIcon, folderAppearance, folderPreviewGrid
        case contactTarget, contactIcon, websiteBrowser
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        name = try values.decode(String.self, forKey: .name)
        children = try values.decode([GroupItem].self, forKey: .children)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
        folderCover = try values.decodeIfPresent(FolderCover.self, forKey: .folderCover)
        websiteURL = try values.decodeIfPresent(String.self, forKey: .websiteURL)
        websiteIcon = try values.decodeIfPresent(FolderCover.self, forKey: .websiteIcon)
        guard kind == .website || !values.contains(.websiteBrowser) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Only websites can carry a browser choice"))
        }
        websiteBrowser = try values.decodeIfPresent(WebsiteBrowser.self, forKey: .websiteBrowser)
        guard kind == .folder || (!values.contains(.folderAppearance) && !values.contains(.folderPreviewGrid)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Only folders can carry folder presentation fields"))
        }
        folderAppearance = try values.decodeIfPresent(SavedGroupAppearance.self, forKey: .folderAppearance)
        folderPreviewGrid = try values.decodeIfPresent(FolderPreviewGrid.self, forKey: .folderPreviewGrid)
        guard kind == .contact || (!values.contains(.contactTarget) && !values.contains(.contactIcon)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Only contacts can carry contact fields"))
        }
        contactTarget = try values.decodeIfPresent(ContactTarget.self, forKey: .contactTarget)
        contactIcon = try values.decodeIfPresent(FolderCover.self, forKey: .contactIcon)
    }
}

public struct SavedGroup: Codable, Sendable, Equatable, Identifiable {
    public static let maximumItems = 200
    /// Four nested folders; the fourth can still hold leaf items and empty cells.
    public static let maximumDepth = 4
    public static let maximumNameLength = 80

    public var id: UUID
    public var name: String
    public var items: [GroupItem]
    public var updatedAt: Date
    public var appearance: SavedGroupAppearance?

    public init(id: UUID = UUID(), name: String, items: [GroupItem] = [], updatedAt: Date = Date(),
                appearance: SavedGroupAppearance? = nil) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.items = items
        self.updatedAt = updatedAt
        self.appearance = appearance
    }

    public var resolvedAppearance: SavedGroupAppearance { appearance ?? .default }

    public func effectiveStyle(useGroupAppearance: Bool, widgetStyle: FolderStyle) -> FolderStyle {
        useGroupAppearance ? resolvedAppearance.style : widgetStyle
    }

    /// Resolve a whole appearance, not individual fields, at a strict folder
    /// path. Invalid paths return nil instead of accidentally editing the root.
    public func resolvedAppearance(at path: [UUID]) -> SavedGroupAppearance? {
        guard path.count <= Self.maximumDepth else { return nil }
        var current = items
        var appearance = resolvedAppearance
        for id in path {
            guard let folder = current.first(where: { $0.id == id && $0.kind == .folder }) else { return nil }
            if let override = folder.folderAppearance { appearance = override }
            current = folder.children
        }
        return appearance
    }

    /// The scope's own override, before inheritance. Nil also represents an
    /// invalid path; callers can distinguish that with items(at:).
    public func appearanceOverride(at path: [UUID]) -> SavedGroupAppearance? {
        guard path.count <= Self.maximumDepth else { return nil }
        guard let id = path.last else { return appearance }
        return items(at: Array(path.dropLast()))?.first { $0.id == id && $0.kind == .folder }?.folderAppearance
    }

    /// A failed validation or stale path leaves the complete draft unchanged.
    @discardableResult
    public mutating func setAppearance(_ appearance: SavedGroupAppearance?, at path: [UUID]) -> Bool {
        guard path.count <= Self.maximumDepth, items(at: path) != nil else { return false }
        var candidate = self
        if let id = path.last {
            let parent = Array(path.dropLast())
            guard var siblings = candidate.items(at: parent),
                  let index = siblings.firstIndex(where: { $0.id == id && $0.kind == .folder }) else { return false }
            siblings[index].folderAppearance = appearance
            guard candidate.replaceItems(siblings, at: parent) else { return false }
        } else {
            candidate.appearance = appearance
            guard candidate.isValid else { return false }
        }
        self = candidate
        return true
    }

    public var hasFolderAppearanceOverrides: Bool {
        func containsOverride(_ items: [GroupItem]) -> Bool {
            items.contains { $0.kind == .folder && ($0.folderAppearance != nil || containsOverride($0.children)) }
        }
        return containsOverride(items)
    }

    /// Navigation identity is rooted in the configuration, never the currently
    /// open folder. Old groups and the disabled mode retain their previous key.
    public func navigationKey(baseKey: String, useGroupAppearance: Bool) -> String {
        let key = baseKey + "|group:\(id.uuidString)|\(revision)"
        return hasFolderAppearanceOverrides && useGroupAppearance ? key + "|folder-appearance:on" : key
    }

    public var isValid: Bool {
        guard Self.validName(name), updatedAt.timeIntervalSince1970.isFinite,
              appearance?.isValid ?? true else { return false }
        var count = 0
        var ids = Set<UUID>()
        return Self.validate(items, folderDepth: 0, count: &count, ids: &ids)
    }

    /// Deterministic across processes. Item order, folder membership, names, aliases and appearance
    /// affect the revision; the save timestamp alone does not invalidate a page.
    public var revision: String {
        var content = normalized
        content.updatedAt = Date(timeIntervalSince1970: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(content)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// System actions only, once per normalized name in reading order. Websites
    /// and contacts need no action binding; repeated actions configure once.
    public var allActionNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        func visit(_ items: [GroupItem]) {
            for item in items {
                if item.kind == .action {
                    let key = SavedGroupBinding.normalizedName(item.name)
                    if !key.isEmpty, seen.insert(key).inserted { names.append(item.name) }
                } else if item.kind == .folder {
                    visit(item.children)
                }
            }
        }
        visit(items)
        return names
    }

    /// Counts contact tiles, including repeated numbers with distinct operations.
    public var contactItemCount: Int {
        func count(_ items: [GroupItem]) -> Int {
            items.reduce(0) { $0 + ($1.kind == .contact ? 1 : ($1.kind == .folder ? count($1.children) : 0)) }
        }
        return count(items)
    }

    /// Folder covers, website and contact artwork in both appearances, even when hidden
    /// by the widget environment. Used by persistence, backup and history leases.
    public var coverAssetIDs: Set<FolderCoverAssetID> {
        var result = Set<FolderCoverAssetID>()
        func visit(_ items: [GroupItem]) {
            for item in items {
                if let cover = item.artworkReference { result.formUnion(cover.assetIDs) }
                visit(item.children)
            }
        }
        visit(items)
        return result
    }

    /// Each path component must be a direct child folder of the previous one.
    public func items(at path: [UUID]) -> [GroupItem]? {
        guard path.count <= Self.maximumDepth else { return nil }
        var current = items
        for id in path {
            guard let folder = current.first(where: { $0.id == id && $0.kind == .folder }) else { return nil }
            current = folder.children
        }
        return current
    }

    /// Edits a draft atomically: an invalid tree or stale path leaves it unchanged.
    @discardableResult
    public mutating func replaceItems(_ replacement: [GroupItem], at path: [UUID]) -> Bool {
        guard path.count <= Self.maximumDepth else { return false }
        var candidate = self
        guard Self.replace(replacement, in: &candidate.items, path: ArraySlice(path)), candidate.isValid else { return false }
        self = candidate
        return true
    }

    /// Moves one node (including a whole folder subtree) without copying its ID.
    /// The insertion index refers to the destination after the source is removed.
    @discardableResult
    public mutating func move(itemID: UUID, to destination: [UUID], at index: Int? = nil) -> Bool {
        guard destination.count <= Self.maximumDepth, !destination.contains(itemID),
              items(at: destination) != nil else { return false }
        var candidate = self
        guard let removed = Self.remove(itemID, from: &candidate.items),
              var target = candidate.items(at: destination) else { return false }
        let insertion = index ?? target.count
        guard insertion >= 0, insertion <= target.count else { return false }
        target.insert(removed, at: insertion)
        guard candidate.replaceItems(target, at: destination) else { return false }
        self = candidate
        return true
    }

    var normalized: SavedGroup {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.items = items.map(\.normalized)
        copy.appearance = appearance?.normalized
        return copy
    }

    private static func validName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maximumNameLength && trimmed.utf8.count <= 512
            && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func validate(_ items: [GroupItem], folderDepth: Int, count: inout Int, ids: inout Set<UUID>) -> Bool {
        for item in items {
            count += 1
            guard count <= maximumItems, ids.insert(item.id).inserted else { return false }
            switch item.kind {
            case .action:
                guard validName(item.name), item.displayName.map(validName) ?? true,
                      item.folderCover == nil, item.websiteURL == nil, item.websiteIcon == nil, item.websiteBrowser == nil,
                      item.folderAppearance == nil, item.folderPreviewGrid == nil,
                      item.contactTarget == nil, item.contactIcon == nil,
                      item.children.isEmpty else { return false }
            case .website:
                guard validName(item.name), item.displayName == nil, item.folderCover == nil,
                      item.folderAppearance == nil, item.folderPreviewGrid == nil,
                      item.contactTarget == nil, item.contactIcon == nil,
                      let address = item.websiteURL, WebsiteURL.validated(address) != nil,
                      item.websiteIcon?.isValid ?? true, item.children.isEmpty else { return false }
            case .contact:
                guard validName(item.name), item.displayName == nil, item.children.isEmpty,
                      item.contactTarget != nil, item.contactIcon?.isValid ?? true,
                      item.folderCover == nil, item.websiteURL == nil, item.websiteIcon == nil, item.websiteBrowser == nil,
                      item.folderAppearance == nil, item.folderPreviewGrid == nil else { return false }
            case .spacer:
                guard item.name.isEmpty, item.displayName == nil, item.folderCover == nil,
                      item.websiteURL == nil, item.websiteIcon == nil, item.websiteBrowser == nil,
                      item.folderAppearance == nil, item.folderPreviewGrid == nil,
                      item.contactTarget == nil, item.contactIcon == nil,
                      item.children.isEmpty else { return false }
            case .folder:
                guard validName(item.name), item.displayName == nil, folderDepth < maximumDepth,
                      item.websiteURL == nil, item.websiteIcon == nil, item.websiteBrowser == nil,
                      item.contactTarget == nil, item.contactIcon == nil,
                      item.folderCover?.isValid ?? true,
                      item.folderAppearance?.isValid ?? true,
                      validate(item.children, folderDepth: folderDepth + 1, count: &count, ids: &ids) else { return false }
            }
        }
        return true
    }

    private static func replace(_ replacement: [GroupItem], in items: inout [GroupItem], path: ArraySlice<UUID>) -> Bool {
        guard let next = path.first else { items = replacement; return true }
        guard let index = items.firstIndex(where: { $0.id == next && $0.kind == .folder }) else { return false }
        return replace(replacement, in: &items[index].children, path: path.dropFirst())
    }

    private static func remove(_ id: UUID, from items: inout [GroupItem]) -> GroupItem? {
        if let index = items.firstIndex(where: { $0.id == id }) { return items.remove(at: index) }
        for index in items.indices where items[index].kind == .folder {
            if let removed = remove(id, from: &items[index].children) { return removed }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case id, name, items, updatedAt, appearance }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        items = try values.decode([GroupItem].self, forKey: .items)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        appearance = try values.decodeIfPresent(SavedGroupAppearance.self, forKey: .appearance)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid saved group"))
        }
        self = normalized
    }
}

/// Resolves a layout reference against the actions actually configured in this
/// widget. Multiple matches are an explicit conflict, never a guess at a target.
public struct SavedGroupBinding: Sendable {
    public enum Resolution: Sendable, Equatable {
        case matched(index: Int)
        case missing
        case ambiguous
    }

    private let indices: [String: [Int]]

    public init(actionNames: [String]) {
        var indices: [String: [Int]] = [:]
        for (index, name) in actionNames.enumerated() {
            let key = Self.normalizedName(name)
            if !key.isEmpty { indices[key, default: []].append(index) }
        }
        self.indices = indices
    }

    public static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }

    public func resolve(_ name: String) -> Resolution {
        let matches = indices[Self.normalizedName(name)] ?? []
        guard let index = matches.first else { return .missing }
        return matches.count == 1 ? .matched(index: index) : .ambiguous
    }
}

/// One validated page. The legacy initializer keeps navigation outside the
/// content budget; icon navigation explicitly reserves cells for its controls.
public struct SavedGroupPage: Sendable, Equatable {
    public let path: [UUID]
    public let page: Int
    public let items: [GroupItem]
    public let visibleItems: [GroupItem]
    public let pageCount: Int
    public let folderName: String
    public let capacity: Int
    /// Icon navigation returns exactly `capacity` cells. Legacy mode returns
    /// only the visible item cells, without allocating arbitrary empty padding.
    public let cells: [SavedGroupGridCell]

    public var parentPath: [UUID]? { path.isEmpty ? nil : Array(path.dropLast()) }
    public var canGoBack: Bool { !path.isEmpty }
    public var hasPreviousPage: Bool { page > 0 }
    public var hasNextPage: Bool { page < pageCount - 1 }

    public init(group: SavedGroup, path requestedPath: [UUID] = [], page requestedPage: Int = 0,
                capacity: Int, usesIconNavigation: Bool = false) {
        let capacity = usesIconNavigation ? SavedGroupIconPagination.capacity(capacity) : max(1, capacity)
        let validPath = group.items(at: requestedPath) != nil
        let path = validPath ? requestedPath : []
        let items = group.items(at: path) ?? []
        let ranges = usesIconNavigation
            ? SavedGroupIconPagination.ranges(itemCount: items.count, capacity: capacity, hasParent: !path.isEmpty) : []
        let pageCount = usesIconNavigation ? ranges.count : (items.isEmpty ? 1 : (items.count - 1) / capacity + 1)
        let page = validPath ? min(max(0, requestedPage), pageCount - 1) : 0
        let start = usesIconNavigation ? ranges[page].lowerBound : page * capacity
        let end = usesIconNavigation ? ranges[page].upperBound : start + min(capacity, items.count - start)

        self.path = path
        self.page = page
        self.items = items
        self.capacity = capacity
        self.pageCount = pageCount
        self.visibleItems = Array(items[start..<end])
        self.cells = usesIconNavigation
            ? SavedGroupIconPagination.cells(items: items, range: start..<end, page: page, pageCount: pageCount,
                                            capacity: capacity, hasParent: !path.isEmpty)
            : self.visibleItems.map(SavedGroupGridCell.item)
        if let last = path.last, let parent = group.items(at: Array(path.dropLast())),
           let folder = parent.first(where: { $0.id == last && $0.kind == .folder }) {
            folderName = folder.name
        } else {
            folderName = group.name
        }
    }
}
