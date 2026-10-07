import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget's rendered content: a grid of buttons, nothing else.
///
/// The only interactive element is `Button(intent: LaunchTileIntent(...))`. Each
/// button's job is to hand a URL to the system; see ``LaunchTileIntent`` for why
/// that reaches a third-party app at all. There is intentionally no `Link` here:
/// a `Link` in a widget can only open the containing app.
///
/// ## What the empty space does
///
/// Nothing, and making that true took three attempts.
///
/// A widget's whole surface opens the containing app when tapped — that is the
/// platform's behaviour, `widgetURL` only redirects the tap rather than gating
/// it, and the SDK publishes no hit-region API. (Apple's own widgets do the same:
/// tapping the blank half of a short Calendar widget opens Calendar.) So a folder
/// of four apps with a whole row empty launches AppFolder when the user taps what
/// looks like nothing.
///
/// The fix is ``InertTapShield`` — a no-op button covering the widget, behind the
/// grid — and the two failed attempts before it are documented there, because
/// both failures look identical from the Home Screen and only one of them was
/// about hit areas.
///
/// An earlier version of this comment claimed the space was inert because no
/// `widgetURL` was set. That was wrong in both directions — the default is
/// *tappable*, and a missing `widgetURL` does not disable it — and it is worth
/// recording because the wrong version reads as obviously correct, and the only
/// thing that disproved it was a tap on a real Home Screen.
struct FolderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// How the system is rendering us right now.
    ///
    /// Read because Liquid Glass is not something the app can ask for — Apple's
    /// own words are that the system "removes the background and replaces it
    /// with a themed glass or tinted color effect" once the person picks a
    /// tinted or clear Home Screen appearance, and the developer's whole job is
    /// to make content survive that. The measure of "survive" is this value: in
    /// ``WidgetRenderingMode/accented`` the system tints primary content white
    /// and flattens images, so an app launcher has to say which of its pictures
    /// must resist that — see the icons below.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: FolderEntry

    var body: some View {
        Group {
            if entry.tiles.isEmpty {
                EmptyWidgetView()
            } else if entry.isExpanded, let folder = entry.folder {
                // The folder was opened by tapping its door — see
                // ``ToggleFolderIntent``. Drawn from the same rectangle, so this
                // is a redraw rather than a presentation; nothing left the Home
                // Screen to get here.
                FolderExpandedGrid(entry: entry, folder: folder, family: family)
            } else {
                FolderGrid(entry: entry, family: family)
                // No inset applied out here any more. The widget disables the
                // system's content margins so a painted plate can reach the
                // widget's edge — see `AppFolderWidget.swift` — and this view
                // used to put the system's margin back with
                // `.padding(contentMargins)`. That inset is the grid's to choose
                // now, because the size setting moves it: at the large end the
                // icons are meant to sit near the edge, and a pad applied out
                // here would have overruled it. `FolderGrid` applies
                // `FolderGridMetrics/margin` instead, which is the same 18 pt at
                // the standard setting.
            }
        }
    }
}

private struct FolderGrid: View {
    let entry: FolderEntry
    let family: WidgetFamily

    /// How many icons fit across, per widget size.
    ///
    /// Three for the two wide families rather than four: at four the icons come
    /// out smaller than a Home Screen icon, and the point of a 大文件夹 is that
    /// its contents look like the real things.
    ///
    /// Read from ``FolderGrid/columns(for:)`` rather than written here, because
    /// the timeline provider truncates the folder to the matching
    /// ``FolderGrid/capacity(for:)``. Two hand-written tables would put the
    /// widget's column count and its tile count out of step the next time either
    /// changed — which is exactly what had happened: capacity said four tiles
    /// for Small while this said two columns.
    ///
    /// It is the *folder's* choice, so a 四宫格 folder draws 2 × 2 in the small
    /// widget and still 3 across in medium and large — see ``FolderGrid`` for why
    /// the setting stops at the small size.
    private var columns: Int { entry.style.grid.columns(for: family) }

    /// Whether to draw names under the icons.
    ///
    /// The folder's own answer, at every size. There used to be a rule here that
    /// Small never drew names, on the grounds that a 3 × 3 cell in 170 pt left a
    /// 27 pt icon once a label took its 26% — but that arithmetic was done
    /// against a grid inset by the system's 18 pt margin on each side, which
    /// wasted 21% of the widget's width on a margin nobody had asked for. The
    /// grid sizes its own margin now (see ``FolderGridMetrics/margin``), so the
    /// same nine cells start from a 134 pt block instead of 151 pt of
    /// already-shrunk space, and a labelled icon comes out at about 38 pt.
    ///
    /// Worth stating plainly, because it is the kind of rule that outlives its
    /// reason: the thing that was wrong was never the label, it was the margin.
    private var showsTitles: Bool { entry.style.showsTitles }

    /// Tiles that actually have artwork, so a sparse folder doesn't leave gaps.
    ///
    /// Artwork only. A tile whose *scheme* is a guess is deliberately not filtered
    /// out here, and the attempt to do so was reverted: withholding every guessed
    /// tile costs the user the ones that work to spare them the ones that don't,
    /// and it is the *wrong* guesses that pay for it — 票牛's guess was `pner://`
    /// where the real scheme is `piaoniu://`, and this rule would have answered a
    /// wrong guess by making the app disappear instead of by fixing it.
    ///
    /// The failure it was meant to prevent is not silent and not permanent: a
    /// wrong scheme opens the 打不开 alert, and the editor lists the alternatives
    /// one tap away. A missing icon, by contrast, is invisible — the app simply
    /// is not there and nothing says why. That is the difference that makes one
    /// worth filtering and the other not.
    private var drawable: [FolderTile] {
        entry.tiles.filter { tile in
            tile.appStoreID != nil || tile.customIconName != nil || tile.symbolName != nil
        }
    }

    /// How many apps this widget shows as apps.
    ///
    /// One less than the grid's cells, because the last cell is the door. Read
    /// from the same ``FolderGrid/capacity(for:)`` the timeline provider truncates
    /// with, so the tiles handed in and the cells laid out cannot disagree.
    private var capacity: Int { entry.style.grid.capacity(for: family) }

    /// The cell that opens the folder, or `nil` when nothing has overflowed.
    ///
    /// Computed from the folder's *full* tile count, not from what the timeline
    /// provider handed over: the provider has already truncated to `capacity`, so
    /// asking it whether anything was cut off would always answer no.
    private var nestedCell: Int? {
        entry.style.grid.nestedCell(for: family, tileCount: entry.totalTileCount)
    }

    var body: some View {
        // A tile with nothing to draw is a blank rounded rectangle with a label,
        // which reads as a broken image rather than as an app. Until the app has
        // cached artwork for it, leave it out.
        let tiles = drawable.isEmpty ? entry.tiles : drawable

        // The container the grid divides up is the whole widget, because the
        // grid applies the outer margin itself — see
        // `FolderGridMetrics/margin`. `\.widgetContentMargins` is no longer read
        // anywhere: it held the system's 18 pt, and the size setting now decides
        // that number instead.
        GeometryReader { proxy in
            // Sized for the *grid*, which is one cell bigger than the app count
            // when the door is showing. Laying out `tiles.count` cells instead
            // would make the icons grow the moment a folder overflowed, which is
            // the opposite of what the door is for.
            let metrics = FolderGridMetrics(
                tileCount: nestedCell == nil ? tiles.count : capacity + 1,
                columns: columns,
                in: proxy.size,
                showsTitles: showsTitles,
                iconScale: entry.style.iconScale
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            if nestedCell == index {
                                NestedTileButton(
                                    folderID: entry.folder?.id,
                                    overflow: overflowCount(shown: tiles.count),
                                    entry: entry,
                                    showsTitles: showsTitles,
                                    metrics: metrics
                                )
                                .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else if tiles.indices.contains(index) {
                                // The resolved value, not `entry.style`, so a
                                // Small widget draws no label even though the
                                // folder asked for one — see `showsTitles`.
                                TileButton(
                                    tile: tiles[index],
                                    style: entry.style,
                                    showsTitles: showsTitles,
                                    metrics: metrics
                                )
                                .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else {
                                // A grid that is not full needs the empty cells
                                // to exist, or the icons left-align and the whole
                                // folder reads as off-centre. They need no tap
                                // handling of their own — the shield behind the
                                // grid already covers them, and the regions the
                                // grid does not reach.
                                Color.clear
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            }
                        }
                    }
                }
            }
            // The tap shield, over the *whole* widget rather than over the empty
            // cells. See ``InertTapShield`` for why covering only the cells a
            // tile is missing from was not enough.
            .background {
                InertTapShield()
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            // The grid's own margin, spent explicitly. It used to come out right by
            // accident: the frame below centred its child, so a margin baked into
            // the metrics landed evenly on both sides. Anchoring to the top takes
            // that away, and the margin has to be applied rather than assumed.
            .padding(metrics.margin)
            // Anchored to the top, not centred. A folder with fewer than nine
            // tiles leaves a whole empty row, and where that row goes is the
            // difference between "this folder has four apps" and "this folder has
            // four apps and the rest are missing". Centred, the icons drift down
            // and the widget reads as the second one; flush with the top they read
            // as a list that happens to be short.
            //
            // The horizontal axis stays centred — the rows are built from
            // `metrics.columns` cells whatever the tile count, so a short folder is
            // already symmetric across the widget. Only the vertical is anchored,
            // because the vertical is the direction the shortfall is measured in.
            //
            // The editor's preview has always drawn it this way (`FolderPreviewGrid`
            // passes `.top`); this is the widget catching up, which is the drift
            // ``FolderGridMetrics`` exists to stop.
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
    }

    /// How many apps are behind the door: everything the widget is not drawing.
    ///
    /// Counted from the *full* folder against what actually got drawn, and
    /// deliberately not from `capacity`. The artwork filter above means the drawn
    /// count can be lower than the capacity — a tile with no cached icon is left
    /// out rather than drawn as a blank square — and a badge that counted the
    /// missing ones as "behind the door" would promise apps the user is not going
    /// to find there.
    private func overflowCount(shown: Int) -> Int {
        // Counted from what the door actually holds rather than as
        // `totalTileCount - shown`. Those two agree only while every tile has
        // artwork: a tile with none is dropped from the grid, so `shown` falls
        // below the capacity while the door keeps hiding everything past it —
        // and the badge would then undercount by exactly the tiles that were
        // dropped. The badge, the preview and the expansion all read this one
        // list, so they cannot promise different things.
        entry.drawableHiddenTiles.count
    }
}

/// The grid's last cell when a folder holds more apps than cells: a small grid of
/// what is behind it, a count, and a tap that opens the folder.
///
/// ## Why this is a `Button(intent:)` and no longer a `Link`
///
/// It used to be a `Link` to `appfolder://folder?id=…`, which opened AppFolder
/// and let it present a sheet. That is a visible hop through another app for
/// something the user asked to see without leaving the Home Screen. The tap now
/// runs ``ToggleFolderIntent`` in the widget's own process, which stores which
/// folder is open and asks WidgetKit for a fresh timeline — so the folder opens
/// *here*, in the same rectangle, with no app launching at all.
///
/// The `Link` survives as the fallback for when there is nowhere to store that
/// state. Note which case that is: **not** "the App Group is unreachable" — the
/// intent and the render share a process, so the tap works without the App Group
/// — but the genuinely unavailable case, where ``WidgetState/isAvailable`` is
/// false and the tap would otherwise do nothing. An app that has to be launched
/// is worse than an in-place expansion, and better than a dead cell.
///
/// ## What it draws
///
/// Not the next app. A folder of twelve in a nine-cell grid shows eight apps and
/// this; showing the ninth as app number nine would leave eleven behind a door
/// the user cannot see, which is indistinguishable from losing them.
///
/// The miniatures are the four apps the door is hiding, at a quarter scale, so
/// the cell says *what* is inside rather than only *how much*. They come from the
/// same cached artwork the full-size cells use; a folder with no artwork cached
/// falls back to the symbols, and the count carries the cell either way.
private struct NestedTileButton: View {
    let folderID: UUID?
    /// How many apps the grid is not drawing. Never zero: the caller only builds
    /// this cell when something overflowed.
    let overflow: Int
    let entry: FolderEntry
    let showsTitles: Bool
    let metrics: FolderGridMetrics

    /// Whether the door can be opened at all.
    ///
    /// A link needs the folder's id, and the id is absent only when the widget is
    /// previewing a folder that does not exist yet. Drawing the cell inert in
    /// that case is the same choice ``TileButton`` makes for a tile with nowhere
    /// to go: a control that does nothing when tapped is worse than one that is
    /// visibly not a control.
    private var destination: URL? {
        folderID.flatMap(LaunchLink.folderURL(for:))
    }

    var body: some View {
        // In-place expansion is the real path: an intent in the widget's own
        // process, no app launch, no hop. It needs somewhere to remember which
        // folder is open — see ``WidgetState/isAvailable`` for what "somewhere"
        // means and why a broken App Group is not the condition that disables it.
        if let folderID, WidgetState.isAvailable {
            Button(intent: ToggleFolderIntent(folderID: folderID.uuidString)) { label }
                .buttonStyle(.plain)
        } else if let destination {
            // Nowhere to store the state, so the only way to show more is the old
            // one: open AppFolder and let it. Reachable in practice only for a
            // folder with no id — the same case ``destination`` is already nil
            // for — which is why the cell then falls through to `label` inert.
            Link(destination: destination) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// How big one miniature is, and how far apart they sit, as a share of the cell.
    ///
    /// Proportions of ``FolderGridMetrics/iconSide`` rather than points, because
    /// this cell is drawn at wildly different sizes — about 37 pt in a small
    /// widget, roughly twice that in the editor's preview — and a fixed number
    /// would be a speck at one end and a smear at the other.
    ///
    /// The first cut of this filled the cell: a flexible 2 × 2 grid with 1 pt
    /// gaps, which made the four miniatures read as one blurry rectangle rather
    /// than as four apps, and what a preview of a folder has to be is legible as
    /// *things*. A miniature is a little under a third of the cell with a gap
    /// near 8% of it, so the block covers about 64% and the rest is the room the
    /// cell's rounded corner and the badge need.
    private static let miniShare: CGFloat = 0.28
    private static let miniSpacingShare: CGFloat = 0.08

    private var miniSide: CGFloat { metrics.iconSide * Self.miniShare }
    private var miniSpacing: CGFloat { metrics.iconSide * Self.miniSpacingShare }

    private var label: some View {
        VStack(spacing: metrics.titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)

                // Two rows of two rather than a `LazyVGrid` of flexible columns:
                // with a fixed size the four have to be placed, not stretched,
                // and an `HStack` of fixed frames says that without a
                // `GridItem(.flexible())` suggesting otherwise.
                VStack(spacing: miniSpacing) {
                    HStack(spacing: miniSpacing) {
                        miniIcon(at: 0)
                        miniIcon(at: 1)
                    }
                    HStack(spacing: miniSpacing) {
                        miniIcon(at: 2)
                        miniIcon(at: 3)
                    }
                }
                // The badge hangs off the *block's* corner, not the cell's.
                //
                // Anchoring it to the cell left it stranded in the margin,
                // sharing an alignment with nothing: the block is centred and
                // inset, so a badge pinned to the cell's corner sits visibly
                // outside and below the last miniature with a gap in between.
                // On the block's corner it reads as a label attached to the
                // thing it counts.
                .overlay(alignment: .bottomTrailing) {
                    Text("+\(overflow)")
                        .font(.system(size: max(7, metrics.iconSide * 0.20), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, metrics.iconSide * 0.06)
                        .padding(.vertical, metrics.iconSide * 0.015)
                        .background(.black.opacity(0.6), in: Capsule())
                        .offset(x: miniSpacing * 0.5, y: miniSpacing * 0.5)
                }
            }
            .frame(width: metrics.iconSide, height: metrics.iconSide)

            if showsTitles {
                // A name, not a count: the count is already on the badge, and
                // "更多" is what the cell does. Every other cell in this grid
                // carries the app it opens, so a word is the consistent choice.
                Text("更多")
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(entry.style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }

    /// One miniature, or a blank if the folder has fewer than four apps behind
    /// the door.
    ///
    /// A blank rather than a repeat or a symbol: with three apps hidden, three
    /// miniatures plus one empty slot is the truth, and filling the fourth would
    /// overstate what the door opens onto.
    /// The radius follows the *miniature's* side, not the cell's.
    ///
    /// The first cut passed ``FolderGridMetrics/cornerRadius`` straight through
    /// on the reasoning that it is already the system icon's 22% proportion. It
    /// is — of the *cell*. At a third the size the same absolute radius is 73% of
    /// the miniature's side, which draws a circle. The proportion is what has to
    /// be preserved, not the number.
    @ViewBuilder
    private func miniIcon(at slot: Int) -> some View {
        let hidden = entry.drawableHiddenTiles
        if hidden.indices.contains(slot) {
            WidgetIcon(tile: hidden[slot], cornerRadius: miniSide * 0.22)
                .frame(width: miniSide, height: miniSide)
        } else {
            Color.clear
                .frame(width: miniSide, height: miniSide)
        }
    }

    }

/// The expanded folder: the apps its door was hiding, a way back, and a way
/// forward when there is more than one page.
///
/// Not the whole folder. The apps the collapsed grid already draws are on the
/// Home Screen behind this widget, and repeating them here would fill the first
/// page with what the user could already see — burying the apps they tapped the
/// door to reach. The door previews some of what is behind it; this is all of it.
///
/// ## Why this is a second grid rather than a mode of the first
///
/// The collapsed grid and this one answer different questions. The collapsed one
/// draws `grid.capacity` apps and a door, and its whole design is about the door
/// — the reservation, the position, the rule that adding a tenth app moves
/// nothing. This one draws however many apps the folder has, paged, with a back
/// cell where the door was. Folding them into one view would mean every invariant
/// the collapsed grid is tested for — see `WidgetGridTests`, which is deliberately
/// untouched by this feature — would need re-deriving under a flag.
///
/// So they share what is genuinely shared and nothing more: the same
/// ``FolderGridMetrics`` for geometry, the same ``TileButton`` for an app, and
/// the same outer padding and top alignment that position the grid inside the
/// widget.
///
/// ## Sizing
///
/// ``FolderGridMetrics`` is handed the **cell count**, not the number of apps on
/// the page. That keeps `rows` a constant of the family, so pages are
/// pixel-identical and icons do not resize as the user pages. Passing the app
/// count instead would make a light final page draw bigger icons than the full
/// one before it, which reads as the widget zooming.
private struct FolderExpandedGrid: View {
    let entry: FolderEntry
    let folder: Folder
    let family: WidgetFamily

    /// Laid out over what the door hides, not over the whole folder — see the
    /// type's own note. The count comes from ``tiles``, which is the *filtered*
    /// list, because the layout's `appCount` decides how many cells the pages
    /// hold: counting a tile the expansion will not draw would leave the last
    /// page with a gap where the withheld app should have been. Passing what is
    /// actually drawn keeps the pages full.
    private var layout: FolderExpansionLayout {
        FolderExpansionLayout(
            family: family,
            grid: entry.style.grid,
            appCount: tiles.count
        )
    }

    /// The apps to draw: the hidden ones, in folder order.
    ///
    /// ``FolderEntry/drawableHiddenTiles`` rather than ``FolderEntry/hiddenTiles``,
    /// so the tiles the expansion declines to draw are exactly the ones the door's
    /// preview and badge already left out. The three have to agree, or the door
    /// promises an app the expansion then fails to show.
    private var tiles: [FolderTile] { entry.drawableHiddenTiles }

    private var page: Int { layout.clampedPage(entry.expandedPage) }

    /// The folder's own answer, at every size — including in the expanded state,
    /// so opening a folder does not change whether its apps are named.
    private var showsTitles: Bool { entry.style.showsTitles }

    var body: some View {
        GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: layout.cellCount,
                columns: layout.columns,
                in: proxy.size,
                showsTitles: showsTitles,
                iconScale: entry.style.iconScale
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let cell = row * metrics.columns + column
                            cellView(cell, tiles: tiles, metrics: metrics)
                        }
                    }
                }
            }
            // Same shield as the collapsed grid, and for the same reason: the
            // widget's surface opens AppFolder by default, and the gaps in a
            // short final page must not be taps that launch another app.
            .background {
                InertTapShield()
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(metrics.margin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Int, tiles: [FolderTile], metrics: FolderGridMetrics) -> some View {
        switch layout.role(forCell: cell, onPage: page) {
        case .back:
            FolderCellButton(
                systemImage: "chevron.backward",
                title: "返回",
                metrics: metrics,
                showsTitles: showsTitles,
                style: entry.style,
                intent: ToggleFolderIntent(folderID: folder.id.uuidString)
            )

        case .next:
            // Carries the page it was drawn on, so the advance starts from what
            // the user saw and the button's identity changes with the page — see
            // ``AdvanceFolderPageIntent``.
            FolderCellButton(
                systemImage: "ellipsis",
                title: "更多",
                metrics: metrics,
                showsTitles: showsTitles,
                style: entry.style,
                intent: AdvanceFolderPageIntent(folderID: folder.id.uuidString, page: page)
            )

        case .app(let index):
            // Drawn from the full list, and never renumbered: a tile whose
            // artwork has not been cached still occupies its cell so the paging
            // arithmetic and what is on screen keep agreeing.
            if tiles.indices.contains(index) {
                TileButton(
                    tile: tiles[index],
                    style: entry.style,
                    showsTitles: showsTitles,
                    metrics: metrics
                )
                .frame(width: metrics.iconSide, height: metrics.cellHeight)
            } else {
                Color.clear.frame(width: metrics.iconSide, height: metrics.cellHeight)
            }

        case .empty:
            Color.clear.frame(width: metrics.iconSide, height: metrics.cellHeight)
        }
    }
}

/// A cell that runs an intent rather than opening an app: the way back, and the
/// way forward.
///
/// Shares ``TileLabel``'s shape — a rounded tile with a symbol and an optional
/// name — because these sit in a grid of app icons and a differently-shaped cell
/// would read as chrome rather than as part of the folder.
private struct FolderCellButton<Intent: AppIntent>: View {
    let systemImage: String
    let title: String
    let metrics: FolderGridMetrics
    let showsTitles: Bool
    let style: FolderStyle
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: metrics.titleSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                        .fill(.fill.tertiary)
                    Image(systemName: systemImage)
                        .font(.system(size: metrics.iconSide * 0.34, weight: .semibold))
                        .foregroundStyle(style.titleStyle)
                }
                .frame(width: metrics.iconSide, height: metrics.iconSide)

                if showsTitles {
                    Text(title)
                        .font(.system(size: metrics.titleFontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(style.titleStyle)
                        .frame(width: metrics.iconSide)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: metrics.iconSide, height: metrics.cellHeight)
    }
}

/// The no-op button that makes the widget's non-icon surface inert.
///
/// A widget's whole surface opens the containing app when tapped, and nothing in
/// the SDK turns that off — `widgetURL` redirects the tap rather than gating it,
/// and there is no hit-region API. Apple's own widgets behave the same way. A
/// folder holding four apps should not launch AppFolder because someone tapped
/// the space where the other five are not.
///
/// So that surface is covered by a `Button` whose intent does nothing: a button
/// is a tap target the system routes to instead of falling through to the
/// widget's default action.
///
/// ## Why it covers everything, and why the first two attempts failed
///
/// This started as one no-op button per *empty cell*, which did not work, for two
/// reasons that are worth recording because both make the failure look
/// identical from the Home Screen:
///
/// 1. A transparent `Color.clear` label has no hit area, so the button was never
///    clickable and every tap went straight through. Fixed by `contentShape`.
/// 2. Even clickable, the cells were the wrong region. The `Grid` is built from
///    `metrics.rows`, and `rows` is derived from the *tile count* — so a
///    four-tile folder lays out two rows and the bottom third of the widget is
///    not part of that `Grid` at all. Neither is the outer margin, nor the slack
///    under a grid that is shorter than its container. Taps there met no button,
///    empty cell or not.
///
/// Covering the whole widget removes the need to reason about which regions the
/// layout happens to leave bare. It is placed behind the grid, so tiles still
/// take their own taps; everything else lands here.
///
/// It draws nothing on purpose: no shape, no tint, no highlight, and no
/// accessible element for what is genuinely a gap in the folder.
private struct InertTapShield: View {
    var body: some View {
        Button(intent: InertTapIntent(cell: 0)) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One tile, routed by its strategy.
///
/// The two routes are not interchangeable and the branch is the interesting part
/// of this view:
///
/// * A `Link` opens **the containing app** — Apple's own words — so it cannot
///   reach a third-party app by itself. What it *can* do is open AppFolder with
///   the target attached, and AppFolder makes the second hop. That is the
///   `.bounce` route, and it is the only thing that works for a custom scheme.
/// * A `Button(intent:)` hands the URL to the system to open. The system is
///   allowed to route anywhere, but `OpenURLIntent` reaches apps through their
///   universal links, not custom schemes. That is `.universalLink`.
///
/// Both routes can come up empty — a tile edited down to a malformed URL, or a
/// "直接打开" tile whose app has no link — and the answer is the same for both:
/// draw the icon and make it inert. A `Link` to nothing, or an `OpenURLIntent`
/// built from a scheme, would render as a *working* tile that does nothing when
/// tapped, which is the failure mode this whole design is arranged around
/// making impossible.
private struct TileButton: View {
    let tile: FolderTile
    let style: FolderStyle
    /// Whether this tile's name is drawn, which is the grid's answer and not
    /// necessarily the folder's — see `FolderGrid/showsTitles`.
    let showsTitles: Bool
    let metrics: FolderGridMetrics

    var body: some View {
        // The route is derived from the tile, not read from a stored preference —
        // see `FolderTile/launchRoute`. The editor no longer offers a choice, so
        // the only thing that could disagree is a tile written by an older build,
        // and deriving it here means those start working correctly too.
        switch tile.launchRoute {
        case .universalLink:
            if let intent = try? OpenLinkIntent(tile: tile) {
                Button(intent: intent) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }

        case .bounce:
            if let target = tile.url, let bounce = LaunchLink.bounceURL(for: target) {
                Link(destination: bounce) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }

        case .systemShortcut:
            // Configured by hand in the QuickLaunch widget, not here. A tile in
            // a folder grid cannot carry one, because the user picks a shortcut
            // per configuration slot and a grid has nine of them.
            label
        }
    }

    private var label: TileLabel {
        TileLabel(tile: tile, style: style, showsTitles: showsTitles, metrics: metrics)
    }
}

/// The icon, and the name under it when the folder asks for one.
///
/// The label is off by default and was removed deliberately — it costs the one
/// thing it was good for, telling two entries apart when the artwork is missing
/// or wrong, so the fallback carries that weight instead: a tile with no image
/// draws its SF Symbol *large*, in the middle of its square. What brings it back
/// is a plate the user painted, because a name is legible on a colour we chose
/// and merely decorative on the system's.
///
/// The geometry is shared with the app's editor preview (``FolderGridMetrics``),
/// so what the user arranges is what they get — including how much of a cell the
/// name is allowed to take, which is why ``FolderGridMetrics/labelHeight``
/// exists rather than a font size written here.
private struct TileLabel: View {
    let tile: FolderTile
    let style: FolderStyle
    /// Whether to draw the name. Separate from ``style`` because the grid can
    /// decide names do not fit at this size — the colour comes from the style
    /// either way, which is why both are here.
    let showsTitles: Bool
    let metrics: FolderGridMetrics

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            WidgetIcon(tile: tile, cornerRadius: metrics.cornerRadius)
                .frame(width: metrics.iconSide, height: metrics.iconSide)

            if showsTitles {
                Text(tile.title)
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    // Shrinks rather than truncates: a name is worth reading, and
                    // "微信" cut to "微…" tells the user nothing. The floor is
                    // where it stops shrinking and starts eliding.
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }
}

/// Icons inside a widget must come from a file the widget can reach, so artwork
/// is read from the App Group container that ``IconStore`` writes into.
///
/// Three sources, in the order the tile prefers them: user-chosen artwork, App
/// Store artwork, and an SF Symbol. The load is synchronous on purpose — see
/// ``WidgetIconCache/image(for:)``.
private struct WidgetIcon: View {
    let tile: FolderTile
    var cornerRadius: CGFloat = 8

    /// Read here rather than passed down, because this is the only place that
    /// needs it and the value is already in the environment.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if let image = tile.cachedIcon {
                // The icon is a *picture of another app*, not decoration, and in
                // Liquid Glass's accented mode the system tints opaque images to
                // a single flat white — which would turn a folder of nine apps
                // into nine identical white blobs. `accentedDesaturated` is the
                // documented middle path for a full-color image the person still
                // has to recognise: the shape and relative luminance survive,
                // the saturation is the part that gives way to the glass. In
                // every other rendering mode there is nothing to yield to, so
                // the artwork stays exactly as the app cached it.
                //
                // Both modifiers here are declared on `Image` and return
                // `some View`, so the order is not a style choice: `resizable`
                // has to come first and `scaledToFit` (a `View` method) has to
                // come last, or one of them is gone by the time it is reached.
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(
                        renderingMode == .accented ? .accentedDesaturated : .fullColor
                    )
                    .scaledToFit()
            } else if let symbol = tile.symbolName {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        // Large, because there is no label to read any more.
                        Image(systemName: symbol)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .foregroundStyle(.secondary)
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Reads pre-downloaded icon data. The widget does not do its own networking:
/// a timeline refresh has a tight budget and artwork is the app's job.
///
/// Reading is **synchronous**, which is unusual for a file read and deliberate.
/// The alternative — `Image(uiImage:)` arriving a frame late from a `.task` —
/// renders one frame of placeholder and is not obviously wrong until you look at
/// a screenshot. Widget rendering has a budget measured in milliseconds and the
/// app keeps the artwork in its own cache, so by the time a widget draws, the
/// bytes are already in the page cache and this is a `memcpy`.
///
/// The cache is a plain class with a lock rather than an actor: an actor's
/// methods are `async`, which is the thing being avoided.
final class WidgetIconCache: @unchecked Sendable {
    static let shared = WidgetIconCache()

    private let lock = NSLock()
    private var cache: [String: UIImage] = [:]
    private let directory: URL?

    init() {
        directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppFolderShared.appGroupIdentifier)?
            .appending(path: "Icons", directoryHint: .isDirectory)
    }

    /// The tile's artwork, or nil if there is none cached on disk.
    func image(for tile: FolderTile) -> UIImage? {
        let key = tile.id.uuidString

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let directory else { return nil }

        var read: URL?
        if let name = tile.customIconName {
            read = directory.appending(path: name)
        } else if let id = tile.appStoreID {
            read = directory.appending(path: "\(id).png")
        }
        guard let read, let data = try? Data(contentsOf: read), let image = UIImage(data: data) else {
            return nil
        }

        lock.lock()
        cache[key] = image
        lock.unlock()
        return image
    }
}

extension FolderTile {
    /// Artwork cached by the app, for the widget to draw.
    var cachedIcon: UIImage? {
        #if canImport(UIKit)
        WidgetIconCache.shared.image(for: self)
        #else
        nil
        #endif
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
            Text("打开 AppFolder 添加图块")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

extension Color {
    /// Parses `#RRGGBB`. Returns nil rather than guessing at malformed input.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
