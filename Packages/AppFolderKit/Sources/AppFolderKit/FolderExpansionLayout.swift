import Foundation
import WidgetKit

/// Where the apps an expanded grid shows go, page by page.
///
/// The widget's own view of a folder is *truncated*: it draws as many apps as
/// fit and puts a door in the last cell. Expanding replaces that door with what
/// is behind it — or, when the caller is the direct-launch **panel**, with the
/// whole configuration. Which of the two it is decides whether a cell is spent on
/// a way back; see ``reservesBackCell``.
///
/// Either way the list can be too much for the same rectangle, and a widget has no
/// interactive surface to scroll. So it goes onto pages, and this type decides
/// what is on each one.
///
/// Pure on purpose. It takes the two things the timeline already knows — the
/// widget family and the folder's grid setting — plus a count, and returns
/// indices. It reads no library, no display state, and no defaults, so the whole
/// of it is answerable from a table; see `FolderExpansionLayoutTests`.
///
/// ## The reserved cells
///
/// A page is not all apps. Cell 0 is always the way back, and on a folder that
/// had to be split, the last cell is the way forward. That leaves ``pageSize``
/// apps in between, and ``pageSize`` is the number that makes
/// ``FolderGrid/capacity(for:)`` and this type agree about where the door was.
///
/// Both reservations are the caller's to make, and ``reservesBackCell`` is how it
/// says so. The door's expansion keeps the way back, because the door itself was
/// a cell the user had to find and the expansion is still a view of the *same*
/// grid. The direct-launch panel gives it up: it draws over the whole widget, so
/// the exit is a tap on any blank space, and a cell spent on 返回 would be a cell
/// not spent on an app — seven instead of nine on the common nine-slot grid.
public struct FolderExpansionLayout: Sendable, Equatable {
    /// What one cell of an expanded page is for.
    public enum CellRole: Equatable, Sendable {
        /// Cell 0, on every page, when ``reservesBackCell``: collapse again.
        case back
        /// The last cell of a page that is not the last page: go forward.
        case next
        /// An index into the **full** tile list laid out, not into a page.
        case app(Int)
        /// Nothing to draw. Still inert, via the same tap shield the grid uses.
        case empty
    }

    public let family: WidgetFamily
    public let grid: FolderGrid
    /// How many apps this lays out — the ones behind the door, or the whole
    /// configuration.
    ///
    /// A folder's expansion passes the apps behind the door rather than the whole
    /// folder: the ones the collapsed grid already draws stay there, on the Home
    /// Screen, and repeating them would push what the door promised off the first
    /// page. The direct-launch panel passes every configured app, because a panel
    /// that showed only the overflow would be a view of an eighth of itself.
    public let appCount: Int
    /// How many icons across, from the folder's grid setting.
    public let columns: Int
    /// How many cells the page has — the same rectangle the collapsed grid draws.
    public let cellCount: Int
    /// How many apps fit on one page, after the reserved cells.
    public let pageSize: Int
    public let pageCount: Int
    /// Whether the list was split across pages at all.
    public let isPaged: Bool

    /// Whether cell 0 is spent on a way back.
    ///
    /// `true` for a folder's expansion, whose cell 0 is 返回. `false` for the
    /// direct-launch panel, which exits on a tap anywhere blank and would rather
    /// spend that cell on an app.
    ///
    /// This is not a cosmetic switch: it moves ``pageSize`` by one and changes what
    /// ``role(forCell:onPage:)`` answers for cell 0, so it is decided at
    /// construction and carried rather than re-derived at each use.
    public let reservesBackCell: Bool

    /// Fits `appCount` apps into a page of the family's grid.
    ///
    /// ## How the circular dependency is avoided
    ///
    /// "Reserve a way forward only if there is more to show" and "there is more
    /// to show if it does not fit in the cells that remain" refer to each other.
    /// Written as one equation neither has a solution, so it is written as two
    /// branches decided from `appCount` and `cellCount` alone — never from
    /// `pageSize`, which is what would close the loop. `r` is 1 when a way back is
    /// reserved and 0 when it is not:
    ///
    /// ```swift
    /// fits      = appCount <= c - r
    /// pageSize  = fits ? c - r : c - r - 1
    /// pageCount = fits ? 1 : ceil(appCount / pageSize)
    /// ```
    ///
    /// The branch is not just tidier — it is what makes "reserved a way forward
    /// with nowhere to go" impossible. In the paging branch `appCount > c - r`,
    /// and `pageSize == c - r - 1`, so `pageCount == ceil(appCount / (c - r - 1))
    /// >= 2` for every `c` and `r` the catalogue can produce. A single page can
    /// therefore never carry a next cell. `FolderExpansionLayoutTests` pins that
    /// as a property rather than trusting the arithmetic here to stay right.
    ///
    /// The branch also keeps the common case whole: with the way back reserved, a
    /// folder holding exactly `c - 1` apps — the "full folder plus a door" every
    /// nine-grid folder reaches at nine — expands to **one** page. Always
    /// reserving a next cell would drop it to `c - 2` apps beside a next cell that
    /// leads nowhere. Without the reservation the same trick buys the direct-launch
    /// panel its point: nine apps, which is also the grid that held the door, and
    /// one page.
    public init(family: WidgetFamily, grid: FolderGrid, appCount: Int, reservesBackCell: Bool = true) {
        self.init(
            family: family,
            columns: grid.columns(for: family),
            cellCount: grid.cellCount(for: family),
            appCount: appCount,
            reservesBackCell: reservesBackCell
        )
    }

    /// Fits `appCount` apps into a page of a grid the caller describes directly.
    ///
    /// For the direct-launch **panel**, whose grid is not the user's 九宫格/四宫格
    /// setting. The panel draws over the whole widget and is free to use more cells
    /// than the collapsed grid's capacity sequence allows, so it asks for a shape
    /// rather than inheriting one — and asking here rather than in the view is what
    /// keeps the panel's icons the *same size* in both states: the collapsed grid
    /// sizes its cells from `columns` and `cellCount` alone, so a panel with the
    /// same two numbers draws the same square, and the extra cells cost nothing.
    ///
    /// The default entry point derives both from a ``FolderGrid``; this one is for
    /// the caller that knows what it wants.
    public init(
        family: WidgetFamily,
        columns: Int,
        cellCount: Int,
        appCount: Int,
        reservesBackCell: Bool
    ) {
        let count = max(0, appCount)
        let cells = max(1, cellCount)
        let reserved = reservesBackCell ? 1 : 0
        let fits = count <= cells - reserved

        self.family = family
        // The grid is only carried for the default entry point; a caller that
        // describes its shape directly has no `FolderGrid` to record, and nothing
        // reads this back.
        self.grid = .default
        self.appCount = count
        self.columns = max(1, columns)
        self.cellCount = cells
        self.reservesBackCell = reservesBackCell
        self.pageSize = max(1, fits ? cells - reserved : cells - reserved - 1)
        self.isPaged = !fits
        // Never zero, even with nothing to show: a caller that has to special-case
        // an empty page would be the caller that forgets to.
        self.pageCount = fits ? 1 : (count + pageSize - 1) / pageSize
    }

    // MARK: - Cells

    /// The way back, always the first cell so it lands where the eye starts.
    ///
    /// Only consulted when ``reservesBackCell``; a panel that exits on blank space
    /// starts its apps here instead. See ``firstAppCell``.
    public var backCell: Int { 0 }

    /// The first cell an app may occupy.
    ///
    /// Cell 1 when the way back is reserved, cell 0 when it is not. Every app-cell
    /// calculation goes through this rather than through a literal, so the two
    /// modes cannot disagree about where the apps start.
    public var firstAppCell: Int { reservesBackCell ? 1 : 0 }

    /// The next cell's index — the last cell of the page.
    ///
    /// ## Where the number lands, and why only one case matters
    ///
    /// `pageSize + firstAppCell` is `cellCount - 1` in the paging branch and
    /// `cellCount` in the fitting branch (for either mode, since both branches and
    /// `firstAppCell` move together with ``reservesBackCell``). So the identity that
    /// actually holds —
    ///
    /// ```swift
    /// isPaged ⇒ nextCell == cellCount - 1
    /// ```
    ///
    /// — is conditional, and in the fitting branch this is a cell index *outside*
    /// the grid. That is deliberate rather than sloppy: a list that fits has no way
    /// forward, so there is no cell for the arrow to occupy, and
    /// ``role(forCell:onPage:)`` answers `.empty` from its range guard. The
    /// alternative — clamping to `cells - 1` — would name the *door's* cell on
    /// every fitting layout, which is the one cell that must never draw a next
    /// arrow, since tapping it would collapse the grid the user just opened.
    ///
    /// Valid on every page. What the cell *is* depends on the page — see
    /// ``role(forCell:onPage:)``, which reports `.empty` on the last one.
    public var nextCell: Int { pageSize + firstAppCell }

    /// What the given cell holds on the given page.
    ///
    /// The page is clamped first, so a stale or out-of-range value draws the last
    /// real page rather than nothing.
    public func role(forCell cell: Int, onPage page: Int) -> CellRole {
        guard cell >= 0, cell < cellCount else { return .empty }
        if reservesBackCell, cell == backCell { return .back }

        let page = clampedPage(page)
        let indices = appIndices(onPage: page)
        // The page's apps occupy `firstAppCell ..< firstAppCell + pageSize`.
        // Indexing from the cell rather than from a position in the page keeps a
        // gap from silently shifting every later app.
        let offset = firstAppCell
        if cell >= offset, cell < offset + pageSize,
           indices.contains(indices.lowerBound + cell - offset) {
            return .app(indices.lowerBound + cell - offset)
        }
        // Only a split list has a way forward, and only before the end.
        if cell == nextCell, isPaged, page < pageCount - 1 { return .next }
        return .empty
    }

    /// The tile index a cell draws, or `nil` for back/next/empty.
    ///
    /// The index is into the list this layout was built over — which is what the
    /// caller needs to map back to its own array, and *not* necessarily a
    /// configuration index. See the call site for how the widget makes that last
    /// step.
    public func tileIndex(forCell cell: Int, onPage page: Int) -> Int? {
        if case .app(let index) = role(forCell: cell, onPage: page) { return index }
        return nil
    }

    // MARK: - Pages

    /// Brings a stored page into range.
    ///
    /// The reader clamps rather than the writer, because the writer cannot: the
    /// intent that advances the page has no widget family and so cannot know how
    /// many pages there are. Two ways a stored value goes stale — a list that
    /// shrank after it was written to a high page, and a widget resized to a
    /// denser grid, which changes `pageSize` without anyone touching the page —
    /// and both are handled here rather than by needing to catch them.
    public func clampedPage(_ page: Int) -> Int {
        min(max(0, page), pageCount - 1)
    }

    /// The tile indices drawn on a page, in order.
    ///
    /// Disjoint across pages and, together, exactly `0..<appCount`: this is the
    /// property that says no app is lost and none is drawn twice, and it is
    /// checked as such in the tests rather than by inspecting each page.
    public func appIndices(onPage page: Int) -> Range<Int> {
        let page = clampedPage(page)
        let start = page * pageSize
        let end = min(start + pageSize, appCount)
        // A clamped page can start past the end when the list holds nothing —
        // `Range` traps on `lowerBound > upperBound`, and an empty list is legal.
        return start < end ? start..<end : 0..<0
    }

    /// Which page a tile index is drawn on.
    ///
    /// The inverse of ``appIndices(onPage:)``. Used by the editor to say where an
    /// app will appear, and by tests to confirm the inverse holds.
    public func pageIndex(forTile index: Int) -> Int {
        guard index > 0 else { return 0 }
        return clampedPage(index / pageSize)
    }
}