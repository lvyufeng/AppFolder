import Foundation
import WidgetKit

/// Where the apps an expanded folder is hiding go, page by page.
///
/// The widget's own view of a folder is *truncated*: it draws as many apps as
/// fit and puts a door in the last cell. Expanding replaces that door with what
/// is behind it — not with the whole folder, which would repeat the first apps
/// the user can already see on the Home Screen and bury the ones they tapped to
/// find. The door previews four of the hidden apps; this is where the rest of
/// them live.
///
/// What is behind the door can still be too much for the same rectangle, and a
/// widget has no interactive surface to scroll. So it goes onto pages, and this
/// type decides what is on each one.
///
/// Pure on purpose. It takes the two things the timeline already knows — the
/// widget family and the folder's grid setting — plus a count, and returns
/// indices. It reads no library, no display state, and no defaults, so the whole
/// of it is answerable from a table; see `FolderExpansionLayoutTests`.
///
/// ## The two reserved cells
///
/// A page is not all apps. Cell 0 is always the way back, and on a folder that
/// had to be split, the last cell is the way forward. That leaves
/// ``pageSize`` apps in between, and ``pageSize`` is the number that makes
/// ``FolderGrid/capacity(for:)`` and this type agree about where the door was.
public struct FolderExpansionLayout: Sendable, Equatable {
    /// What one cell of an expanded page is for.
    public enum CellRole: Equatable, Sendable {
        /// Cell 0, on every page: collapse the folder again.
        case back
        /// The last cell of a page that is not the last page: go forward.
        case next
        /// An index into the folder's **full** tile list, not into a page.
        case app(Int)
        /// Nothing to draw. Still inert, via the same tap shield the grid uses.
        case empty
    }

    public let family: WidgetFamily
    public let grid: FolderGrid
    /// How many apps are behind the door — the ones this lays out.
    ///
    /// Not the folder's size. The apps the collapsed grid already draws stay
    /// there, on the Home Screen, and repeating them here would push what the
    /// door promised off the first page. See ``appCount(of:showing:)`` for how
    /// the number is arrived at.
    public let appCount: Int
    /// How many icons across, from the folder's grid setting.
    public let columns: Int
    /// How many cells the page has — the same rectangle the collapsed grid draws.
    public let cellCount: Int
    /// How many apps fit on one page, after the reserved cells.
    public let pageSize: Int
    public let pageCount: Int
    /// Whether the folder was split across pages at all.
    public let isPaged: Bool

    /// Fits `appCount` apps into a page of the family's grid.
    ///
    /// ## How the circular dependency is avoided
    ///
    /// "Reserve a way forward only if there is more to show" and "there is more
    /// to show if it does not fit in the cells that remain" refer to each other.
    /// Written as one equation neither has a solution, so it is written as two
    /// branches decided from `appCount` and `cellCount` alone — never from
    /// `pageSize`, which is what would close the loop:
    ///
    /// ```swift
    /// fits      = appCount <= c - 1
    /// pageSize  = fits ? c - 1 : c - 2
    /// pageCount = fits ? 1 : ceil(appCount / pageSize)
    /// ```
    ///
    /// The branch is not just tidier — it is what makes "reserved a way forward
    /// with nowhere to go" impossible. In the paging branch `appCount > c - 1`,
    /// and `pageSize == c - 2`, so `pageCount == ceil(appCount / (c - 2)) >= 2`
    /// for every `c >= 4` the catalogue can produce. A single page can therefore
    /// never carry a next cell. `FolderExpansionLayoutTests` pins that as a
    /// property rather than trusting the arithmetic here to stay right.
    ///
    /// The branch also keeps the common case whole: a folder holding exactly
    /// `c - 1` apps — the "full folder plus a door" every nine-grid folder
    /// reaches at nine — expands to **one** page. Always reserving a next cell
    /// would drop it to `c - 2` apps beside a next cell that leads nowhere.
    public init(family: WidgetFamily, grid: FolderGrid, appCount: Int) {
        let count = max(0, appCount)
        let cells = grid.cellCount(for: family)
        let fits = count <= cells - 1

        self.family = family
        self.grid = grid
        self.appCount = count
        self.columns = grid.columns(for: family)
        self.cellCount = cells
        self.pageSize = fits ? cells - 1 : cells - 2
        self.isPaged = !fits
        // Never zero, even with nothing to show: a caller that has to special-case
        // an empty page would be the caller that forgets to.
        self.pageCount = fits ? 1 : (count + pageSize - 1) / pageSize
    }

    /// How many apps an expanded folder has to lay out, given the grid it was
    /// opened from.
    ///
    /// ``shown`` is how many the collapsed grid drew, which is the cell count
    /// less the door — but it is passed in rather than derived, because the
    /// collapsed view drops tiles it has no artwork for and only it knows how
    /// many that left. The door counts its previews from the same number
    /// (``FolderEntry/hiddenTiles``), which is what makes the expansion start
    /// exactly where the preview stopped instead of merely near it.
    ///
    /// Clamped at zero: a folder that fits has no door and so nothing to expand,
    /// and a caller that asks anyway gets an empty layout rather than a negative
    /// count that would page backwards.
    public static func appCount(of folder: Folder, showing shown: Int) -> Int {
        max(0, folder.tiles.count - max(0, shown))
    }

    // MARK: - Cells

    /// The way back, always the first cell so it lands where the eye starts.
    public var backCell: Int { 0 }

    /// The next cell's index — the last cell of the page.
    ///
    /// ## Where the number lands, and why only one case matters
    ///
    /// `pageSize + 1` is `cellCount - 1` in the paging branch and `cellCount` in
    /// the fitting branch, since `pageSize` is `cells - 2` in the first and
    /// `cells - 1` in the second. So the identity that actually holds —
    ///
    /// ```swift
    /// isPaged ⇒ nextCell == cellCount - 1 == FolderGrid.capacity(for:)
    /// ```
    ///
    /// — is conditional, and in the fitting branch this is a cell index *outside*
    /// the grid. That is deliberate rather than sloppy: a folder that fits has no
    /// way forward, so there is no cell for the arrow to occupy, and
    /// ``role(forCell:onPage:)`` answers `.empty` from its range guard. The
    /// alternative — clamping to `cells - 1` — would name the *door's* cell on
    /// every fitting layout, which is the one cell that must never draw a next
    /// arrow, since tapping it would collapse the folder the user just opened.
    ///
    /// The paged case is the one the design turns on: the expand tap changes the
    /// role of one cell and moves nothing else, so the beat while the timeline
    /// reloads reads as a state change rather than a re-layout.
    ///
    /// Valid on every page. What the cell *is* depends on the page — see
    /// ``role(forCell:onPage:)``, which reports `.empty` on the last one.
    public var nextCell: Int { pageSize + 1 }

    /// What the given cell holds on the given page.
    ///
    /// The page is clamped first, so a stale or out-of-range value draws the last
    /// real page rather than nothing.
    public func role(forCell cell: Int, onPage page: Int) -> CellRole {
        guard cell >= 0, cell < cellCount else { return .empty }
        if cell == backCell { return .back }

        let page = clampedPage(page)
        let indices = appIndices(onPage: page)
        // Cells 1...pageSize hold the page's apps, in order. Indexing from the
        // cell rather than from a position in the page keeps a gap from silently
        // shifting every later app.
        if cell >= 1, cell <= pageSize, indices.contains(indices.lowerBound + cell - 1) {
            return .app(indices.lowerBound + cell - 1)
        }
        // Only a folder that was split has a way forward, and only before the end.
        if cell == nextCell, isPaged, page < pageCount - 1 { return .next }
        return .empty
    }

    /// The folder-wide tile index a cell draws, or `nil` for back/next/empty.
    public func tileIndex(forCell cell: Int, onPage page: Int) -> Int? {
        if case .app(let index) = role(forCell: cell, onPage: page) { return index }
        return nil
    }

    // MARK: - Pages

    /// Brings a stored page into range.
    ///
    /// The reader clamps rather than the writer, because the writer cannot: the
    /// intent that advances the page has no widget family and so cannot know how
    /// many pages the folder has. Two ways a stored value goes stale — a folder
    /// that shrank after it was written to a high page, and a widget resized to a
    /// denser grid, which changes `pageSize` without anyone touching the page —
    /// and both are handled here rather than by needing to catch them.
    public func clampedPage(_ page: Int) -> Int {
        min(max(0, page), pageCount - 1)
    }

    /// The folder-wide tile indices drawn on a page, in order.
    ///
    /// Disjoint across pages and, together, exactly `0..<appCount`: this is the
    /// property that says no app is lost and none is drawn twice, and it is
    /// checked as such in the tests rather than by inspecting each page.
    public func appIndices(onPage page: Int) -> Range<Int> {
        let page = clampedPage(page)
        let start = page * pageSize
        let end = min(start + pageSize, appCount)
        // A clamped page can start past the end when the folder holds nothing —
        // `Range` traps on `lowerBound > upperBound`, and an empty folder is a
        // legal folder.
        return start < end ? start..<end : 0..<0
    }

    /// Which page a folder-wide tile index is drawn on.
    ///
    /// The inverse of ``appIndices(onPage:)``. Used by the editor to say where an
    /// app will appear, and by tests to confirm the inverse holds.
    public func pageIndex(forTile index: Int) -> Int {
        guard index > 0 else { return 0 }
        return clampedPage(index / pageSize)
    }
}