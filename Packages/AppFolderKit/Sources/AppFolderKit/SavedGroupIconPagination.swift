import Foundation

/// A fixed grid's contents, including its in-grid navigation affordances.
public enum SavedGroupGridCell: Sendable, Equatable {
    case item(GroupItem)
    case parent
    case previous
    case next
    case empty
}

/// Navigation consumes cells rather than a separate title/paging header.
/// A child always reserves its first cell for its parent. Subsequent pages also
/// reserve a previous cell; a next cell is needed only if the rest will not fit.
/// These ranges are also used to locate the folder when returning to its parent.
enum SavedGroupIconPagination {
    static func capacity(_ requested: Int) -> Int {
        // Four is the smallest production grid. At least three controls plus
        // one item must fit, even for a malformed caller-supplied capacity.
        // No valid group can need more than 200 cells; bound padding allocations.
        min(SavedGroup.maximumItems, max(4, requested))
    }

    static func ranges(itemCount: Int, capacity requested: Int, hasParent: Bool) -> [Range<Int>] {
        let capacity = Self.capacity(requested)
        let count = max(0, itemCount)
        guard count > 0 else { return [0..<0] }
        var result: [Range<Int>] = []
        var start = 0
        while start < count {
            let leading = (hasParent ? 1 : 0) + (result.isEmpty ? 0 : 1)
            let withoutNext = capacity - leading
            let remaining = count - start
            let take = remaining <= withoutNext ? remaining : withoutNext - 1
            result.append(start..<(start + take))
            start += take
        }
        return result
    }

    static func cells(items: [GroupItem], range: Range<Int>, page: Int, pageCount: Int,
                      capacity: Int, hasParent: Bool) -> [SavedGroupGridCell] {
        var cells: [SavedGroupGridCell] = []
        if hasParent { cells.append(.parent) }
        if page > 0 { cells.append(.previous) }
        cells.append(contentsOf: items[range].map(SavedGroupGridCell.item))
        // Keep next at the last grid position. A last page uses all remaining
        // cells for items, and any empty cells follow those items.
        let hasNext = page + 1 < pageCount
        let emptyCount = capacity - cells.count - (hasNext ? 1 : 0)
        cells.append(contentsOf: repeatElement(.empty, count: max(0, emptyCount)))
        if hasNext { cells.append(.next) }
        return cells
    }
}
