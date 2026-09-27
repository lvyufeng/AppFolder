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
    /// How wide the grid is worked out at, in points.
    ///
    /// ``FolderGridMetrics`` wants a width to divide up, and the grid is drawn at
    /// wildly different sizes — 56 pt in the folder list, 220 pt in the editor.
    /// So it is laid out once for this width and the whole drawing is scaled to
    /// whatever the container turns out to be. That keeps the two views at
    /// *identical proportions* rather than merely similar ones, which is the
    /// whole reason the metrics type exists.
    var designWidth: CGFloat = 320

    private var metrics: FolderGridMetrics {
        FolderGridMetrics(
            tileCount: tiles.count,
            columns: FolderGridMetrics.columns(forTileCount: tiles.count),
            // Unbounded height: an `aspectRatio` preview knows its width and not
            // its height, and leaving the width as the binding constraint is
            // what a square grid wants anyway.
            in: CGSize(width: designWidth, height: .greatestFiniteMagnitude),
            showsTitles: showsTitles
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
                            if tiles.indices.contains(index) {
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
        .aspectRatio(CGFloat(metrics.columns) / CGFloat(max(1, metrics.rows)), contentMode: .fit)
    }
}

/// A single app icon, with a graceful fallback chain.
struct TileIcon: View {
    let tile: FolderTile
    var side: CGFloat
    var showsTitle: Bool = false
    var titleFontSize: CGFloat?
    var titleSpacing: CGFloat = 1

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: titleSpacing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    // Never a blank square: a symbol is always better than a hole.
                    RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: tile.symbolName ?? "app.dashed")
                                .font(.system(size: side * 0.44))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))

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
