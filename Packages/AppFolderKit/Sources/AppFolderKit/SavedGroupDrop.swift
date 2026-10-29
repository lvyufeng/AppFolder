import Foundation

public struct SavedGroupItemLocation: Sendable, Equatable {
    /// The direct parent folder path, or [] for the root list.
    public let path: [UUID]
    public let index: Int

    public init(path: [UUID], index: Int) {
        self.path = path
        self.index = index
    }
}

/// Content identities are the anchors. Virtual empty cells additionally carry
/// bounded, temporary layout context; none of this adds stored position fields.
public enum SavedGroupDropTarget: Sendable, Hashable {
    case before(itemID: UUID)
    case spacer(itemID: UUID)
    case append(folderID: UUID?)
    /// Offset zero is the first virtual .empty cell on the current last page.
    case vacant(folderID: UUID?, capacity: Int, emptyOffset: Int)
}

public struct SavedGroupDropRequest: Sendable, Equatable {
    public let groupID: UUID
    public let itemID: UUID
    public let expectedRevision: String
    public let target: SavedGroupDropTarget

    public init(groupID: UUID, itemID: UUID, expectedRevision: String, target: SavedGroupDropTarget) {
        self.groupID = groupID
        self.itemID = itemID
        self.expectedRevision = expectedRevision
        self.target = target
    }
}

public enum SavedGroupDropError: Error, Sendable, Equatable {
    case wrongGroup
    case staleRevision
    case invalidGroup
    case sourceNotFound
    case invalidTarget
    case cycle
    /// The complete result would violate tree constraints, including depth or
    /// the total node budget. No partial removal or inserted spacer is applied.
    case invalidResult
}

public enum SavedGroupDropOutcome: Sendable, Equatable {
    case changed
    case unchanged
    case rejected(SavedGroupDropError)
}

extension SavedGroup {
    /// Invalid or ambiguous trees have no location. Display names and visual
    /// grid indices are never used to choose an item.
    public func itemLocation(id: UUID) -> SavedGroupItemLocation? {
        guard isValid else { return nil }
        return Self.dropLocation(id: id, in: items)
    }

    /// Applies one drop atomically. Hovering and cancellation should not call
    /// this method. The caller owns history and the one-use drag session.
    /// All original node fields and updatedAt survive unchanged.
    @discardableResult
    public mutating func applyDrop(_ request: SavedGroupDropRequest) -> SavedGroupDropOutcome {
        guard request.groupID == id else { return .rejected(.wrongGroup) }
        guard isValid else { return .rejected(.invalidGroup) }
        guard request.expectedRevision == revision else { return .rejected(.staleRevision) }
        guard let sourceLocation = Self.dropLocation(id: request.itemID, in: items),
              let source = items(at: sourceLocation.path)?[sourceLocation.index] else {
            return .rejected(.sourceNotFound)
        }
        var candidate = self
        switch request.target {
        case .before(let targetID):
            guard let targetLocation = Self.dropLocation(id: targetID, in: items),
                  let target = items(at: targetLocation.path)?[targetLocation.index], target.kind != .spacer else {
                return .rejected(.invalidTarget)
            }
            if source.id == target.id { return .unchanged }
            guard !targetLocation.path.contains(source.id) else { return .rejected(.cycle) }
            let removalShiftsTarget = sourceLocation.path == targetLocation.path && sourceLocation.index < targetLocation.index
            let insertion = targetLocation.index - (removalShiftsTarget ? 1 : 0)
            guard candidate.move(itemID: source.id, to: targetLocation.path, at: insertion) else {
                return .rejected(.invalidResult)
            }

        case .spacer(let targetID):
            guard let targetLocation = Self.dropLocation(id: targetID, in: items),
                  let target = items(at: targetLocation.path)?[targetLocation.index], target.kind == .spacer else {
                return .rejected(.invalidTarget)
            }
            if source.id == target.id { return .unchanged }
            guard !targetLocation.path.contains(source.id) else { return .rejected(.cycle) }
            // Swap the actual spacer back to the original source position. A
            // remove-then-replace would shift the intended destination cell.
            candidate.items = Self.replacingDropItems(in: items, firstID: source.id, first: target,
                                                     secondID: target.id, second: source)

        case .append(let folderID):
            guard let path = dropDestinationPath(folderID: folderID) else { return .rejected(.invalidTarget) }
            guard !path.contains(source.id) else { return .rejected(.cycle) }
            guard candidate.move(itemID: source.id, to: path) else { return .rejected(.invalidResult) }

        case .vacant(let folderID, let capacity, let emptyOffset):
            guard (4...SavedGroup.maximumItems).contains(capacity), emptyOffset >= 0,
                  let path = dropDestinationPath(folderID: folderID) else { return .rejected(.invalidTarget) }
            guard !path.contains(source.id) else { return .rejected(.cycle) }
            let firstPage = SavedGroupPage(group: self, path: path, capacity: capacity, usesIconNavigation: true)
            let lastPage = SavedGroupPage(group: self, path: path, page: firstPage.pageCount - 1,
                                          capacity: capacity, usesIconNavigation: true)
            let emptyCount = lastPage.cells.filter { $0 == .empty }.count
            guard emptyOffset < emptyCount else { return .rejected(.invalidTarget) }
            // Materialize only the cells that acquire meaning: the vacated
            // source and the virtual empty cells skipped before the new target.
            // Keeping the source cell avoids moving every following item.
            candidate.items = Self.replacingDropItems(in: items, firstID: source.id, first: .spacer())
            guard var destination = candidate.items(at: path) else { return .rejected(.invalidTarget) }
            destination.append(contentsOf: (0..<emptyOffset).map { _ in GroupItem.spacer() })
            destination.append(source)
            guard candidate.replaceItems(destination, at: path) else { return .rejected(.invalidResult) }
        }
        guard candidate.isValid else { return .rejected(.invalidResult) }
        guard candidate != self else { return .unchanged }
        self = candidate
        return .changed
    }

    private func dropDestinationPath(folderID: UUID?) -> [UUID]? {
        guard let folderID else { return [] }
        guard let location = Self.dropLocation(id: folderID, in: items),
              items(at: location.path)?[location.index].kind == .folder else { return nil }
        return location.path + [folderID]
    }

    private static func dropLocation(id: UUID, in items: [GroupItem], path: [UUID] = []) -> SavedGroupItemLocation? {
        for (index, item) in items.enumerated() {
            if item.id == id { return .init(path: path, index: index) }
            if item.kind == .folder, let nested = dropLocation(id: id, in: item.children, path: path + [item.id]) {
                return nested
            }
        }
        return nil
    }

    private static func replacingDropItems(in items: [GroupItem], firstID: UUID, first: GroupItem,
                                           secondID: UUID? = nil, second: GroupItem? = nil) -> [GroupItem] {
        items.map { item in
            if item.id == firstID { return first }
            if item.id == secondID, let second { return second }
            guard item.kind == .folder else { return item }
            var copy = item
            copy.children = replacingDropItems(in: item.children, firstID: firstID, first: first,
                                               secondID: secondID, second: second)
            return copy
        }
    }
}
