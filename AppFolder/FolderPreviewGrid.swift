import AppFolderKit
import SwiftUI

/// The grid of app icons — the "big folder" itself.
///
/// Used in three places with the same look: the widget on the Home Screen, the
/// folder list thumbnail, and the editor preview. The cell maths lives in
/// ``FolderGridMetrics`` so the preview and the widget cannot disagree about
/// where the icons go.
///
/// Icons are rounded rectangles masked to the system's icon shape rather than
/// plain circles, so a third-party app's artwork reads correctly next to real
/// Home Screen icons.
struct FolderPreviewGrid: View {
    let tiles: [FolderTile]
    var showsTitles: Bool = false
    /// How much of the grid goes to icons rather than to the gaps. Not defaulted
    /// through ``FolderGridMetrics/defaultIconScale`` here, because the only
    /// caller with an opinion — the editor — is previewing a folder that has one,
    /// and a silently-different preview is the drift this view exists to avoid.
    var iconScale: Double = FolderGridMetrics.defaultIconScale

    /// How many icons across. Passed in rather than derived from `tiles.count`
    /// because the folder's grid setting decides it: a 四宫格 folder holding six
    /// tiles still draws two across, and deriving from the count would draw three.
    ///
    /// `nil` keeps the old behaviour of choosing by count, which is what the
    /// folder-list thumbnail wants — it has no setting to honour and shows
    /// whatever the folder holds.
    var columns: Int?

    /// Whether the last cell draws the "open the rest" door, and what is behind
    /// it.
    ///
    /// Passed in rather than derived, because the preview is handed an already
    /// truncated tile list — it cannot see the apps that were cut off, and
    /// `tiles.count` therefore cannot tell it whether anything was. The caller
    /// knows both, and the widget resolves the same question the same way, from
    /// ``FolderGrid/nestedCell(for:tileCount:)``.
    ///
    /// `nil` means "this grid has no door", which is what the folder-list
    /// thumbnail wants: it previews a folder's *contents*, not a particular
    /// widget size, so it draws whatever it was given and nothing else.
    var nested: NestedCell?

    /// The apps behind the door, and how many there are in total.
    ///
    /// A struct rather than a bare count so the cell can draw miniatures: a badge
    /// saying "+4" tells the user less than four small icons do, and the whole
    /// point of the cell is to say what is inside without opening it.
    struct NestedCell {
        /// Up to four apps to draw small. Fewer is fine — the cell leaves the
        /// spare slots blank rather than repeating or inventing one.
        var previews: [FolderTile]
        /// Every app behind the door, for the badge.
        var count: Int
    }

    /// How wide the grid is worked out at, in points.
    ///
    /// ``FolderGridMetrics`` wants a width to divide up, and the grid is drawn at
    /// wildly different sizes — 56 pt in the folder list, 220 pt in the editor.
    /// So it is laid out once for this width and the whole drawing is scaled to
    /// whatever the container turns out to be. That keeps the two views at
    /// *identical proportions* rather than merely similar ones, which is the
    /// whole reason the metrics type exists.
    var designWidth: CGFloat = 320

    /// How many cells the grid draws: the tiles it has, or the tiles plus the door
    /// when there is one.
    ///
    /// Deliberately not capped at the cells the grid has room for. The callers
    /// already hand over at most ``FolderGrid/capacity(for:)`` tiles with the
    /// matching column count, so `+ 1` is exactly the cell count — and a cap here
    /// would turn a caller that got that wrong into a grid that silently drops a
    /// row instead of one that is visibly the wrong shape.
    private var cellCount: Int { nested == nil ? tiles.count : tiles.count + 1 }

    private var metrics: FolderGridMetrics {
        FolderGridMetrics(
            tileCount: cellCount,
            columns: columns ?? FolderGridMetrics.columns(forTileCount: cellCount),
            // Unbounded height: an `aspectRatio` preview knows its width and not
            // its height, and leaving the width as the binding constraint is
            // what a square grid wants anyway.
            //
            // `designWidth` is the whole tile, not the space the icons get: the
            // metrics take the size setting's margin off it themselves, and the
            // grid is centred in the container below, so the margin appears
            // without anything here having to apply it.
            in: CGSize(width: designWidth, height: .greatestFiniteMagnitude),
            showsTitles: showsTitles,
            iconScale: iconScale
        )
    }

    var body: some View {
        let metrics = metrics

        return GeometryReader { proxy in
            let unit = proxy.size.width / designWidth

            Grid(horizontalSpacing: metrics.spacing * unit, verticalSpacing: metrics.spacing * unit) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            // The door sits at the end of the tiles, which is
                            // the same cell the widget gives it, because both
                            // reserve it for every full grid rather than only
                            // for the ones that overflow — see
                            // ``FolderGrid/capacity(for:)``.
                            if let nested, index == tiles.count, index < metrics.columns * metrics.rows {
                                NestedCellView(
                                    nested: nested,
                                    side: metrics.iconSide * unit,
                                    cornerRadius: metrics.cornerRadius * unit,
                                    showsTitle: showsTitles,
                                    titleFontSize: metrics.titleFontSize * unit,
                                    titleSpacing: metrics.titleSpacing * unit
                                )
                            } else if tiles.indices.contains(index) {
                                TileIcon(
                                    tile: tiles[index],
                                    side: metrics.iconSide * unit,
                                    showsTitle: showsTitles,
                                    titleFontSize: metrics.titleFontSize * unit,
                                    titleSpacing: metrics.titleSpacing * unit
                                )
                            } else {
                                Color.clear
                                    .frame(width: metrics.iconSide * unit, height: metrics.cellHeight * unit)
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .aspectRatio(
            CGFloat(metrics.columns) / CGFloat(max(1, metrics.rows)),
            contentMode: .fit
        )
    }
}

/// The grid's last cell when a folder holds more apps than cells: a small grid of
/// what is behind it, a count, and — in the widget — a tap that opens it.
///
/// ## Why this is a preview-only type
///
/// The widget draws the same thing, but it cannot share this view. The widget's
/// version has to be wrapped in a `Link` carrying an `appfolder://` URL, and that
/// URL is a widget concern; this one is inert and reachable only through the
/// editor, where a tap should do nothing at all. What the two *do* share is
/// ``FolderGridMetrics``, and that is what matters: the cell is the same size and
/// the miniatures sit at the same inset, so the preview is not lying about the
/// geometry — which is the only thing a preview can be wrong about here.
struct NestedCellView: View {
    let nested: FolderPreviewGrid.NestedCell
    let side: CGFloat
    let cornerRadius: CGFloat
    let showsTitle: Bool
    let titleFontSize: CGFloat
    let titleSpacing: CGFloat

    /// How many miniatures to draw, and how big.
    ///
    /// Read from ``MiniGridDensity`` rather than written out here, which is what
    /// this cell used to do — a second copy of the widget's shares, kept in step
    /// only by a comment asking the next person to change both. The two targets
    /// cannot import each other, so the shared package is the only place the
    /// numbers can live.
    ///
    /// Deliberately the same rule the widget applies: this cell is *the same
    /// cell*, drawn at a different size, and a preview that showed four where the
    /// Home Screen shows nine would be the drift the shared metrics type exists
    /// to prevent.
    private var density: MiniGridDensity {
        MiniGridDensity(cellSide: side)
    }

    private var miniSide: CGFloat { density.miniSide }
    private var miniSpacing: CGFloat { density.spacing }

    var body: some View {
        VStack(spacing: titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)

                VStack(spacing: miniSpacing) {
                    ForEach(0..<density.rows, id: \.self) { row in
                        HStack(spacing: miniSpacing) {
                            ForEach(0..<density.columns, id: \.self) { column in
                                miniIcon(at: row * density.columns + column)
                            }
                        }
                    }
                }
                // The badge hangs off the block's corner rather than the cell's,
                // so it reads as a label on the thing it counts — see the same
                // overlay in `NestedTileButton`.
                .overlay(alignment: .bottomTrailing) {
                    Text("+\(nested.count)")
                        .font(.system(size: max(7, side * 0.20), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, side * 0.06)
                        .padding(.vertical, side * 0.015)
                        .background(.black.opacity(0.6), in: Capsule())
                        .offset(x: miniSpacing * 0.5, y: miniSpacing * 0.5)
                }
            }
            .frame(width: side, height: side)

            if showsTitle {
                // Matches the widget's own label — see the note there for why it
                // is 其他 and not 更多.
                Text("其他")
                    .font(.system(size: titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.secondary)
                    .frame(width: side)
            }
        }
    }

    /// One miniature, or a blank slot when the folder has fewer apps behind the
    /// door than this density draws. The radius is the mini's own, not the cell's
    /// — see the same call in `NestedTileButton` for why.
    @ViewBuilder
    private func miniIcon(at slot: Int) -> some View {
        if nested.previews.indices.contains(slot) {
            TileIcon(
                tile: nested.previews[slot],
                side: miniSide,
                cornerRadius: miniSide * 0.22
            )
        } else {
            Color.clear
                .frame(width: miniSide, height: miniSide)
        }
    }
}

/// A single app icon, with a graceful fallback chain.
struct TileIcon: View {
    let tile: FolderTile
    var side: CGFloat
    var showsTitle: Bool = false
    var titleFontSize: CGFloat?
    var titleSpacing: CGFloat = 1
    /// The icon's corner radius. Defaults to the system's own proportion, which
    /// is what every full-size use wants; the nested cell's miniatures pass their
    /// own, because a proportion has to follow the side it is a proportion *of*.
    var cornerRadius: CGFloat?

    @State private var image: UIImage?

    /// The icon's corner radius, resolved once so the fallback shape and the
    /// clip cannot disagree about it.
    private var radius: CGFloat { cornerRadius ?? side * 0.22 }

    var body: some View {
        VStack(spacing: titleSpacing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    // Never a blank square: a symbol is always better than a hole.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: tile.symbolName ?? "app.dashed")
                                .font(.system(size: side * 0.44))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

            if showsTitle {
                Text(tile.title)
                    // Named by the caller when the grid computed one, so the same
                    // font size travels with the layout it was measured for.
                    .font(.system(size: titleFontSize ?? max(7, side * 0.19)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.secondary)
                    .frame(width: side)
            }
        }
        .task(id: tile.id) {
            image = await IconStore.shared.image(for: tile)
        }
    }
}
