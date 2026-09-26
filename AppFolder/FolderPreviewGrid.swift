import AppFolderKit
import SwiftUI

/// The grid of app icons — the "big folder" itself.
///
/// Used in three places with the same look: the widget on the Home Screen, the
/// folder list thumbnail, and the editor preview. Layout is derived from the
/// number of tiles rather than fixed, because the same folder has to read
/// correctly at every widget size:
///
/// * 1–4 tiles → 2 columns
/// * 5–9 tiles → 3 columns (the classic 大文件夹 square)
/// * 10+ tiles → 4 columns, which is only reachable in the Extra Large widget
///
/// Icons are rounded rectangles masked to the system's icon shape rather than
/// plain circles, so a third-party app's artwork reads correctly next to real
/// Home Screen icons.
struct FolderPreviewGrid: View {
    let tiles: [FolderTile]
    var showsTitles: Bool = false
    var iconSize: CGFloat?

    private var columns: Int {
        switch tiles.count {
        case 0...4: 2
        case 5...9: 3
        default: 4
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let count = max(columns, 1)
            let spacing = max(2, proxy.size.width * 0.055)
            let side = (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let rows = (tiles.count + count - 1) / count
            let totalHeight = side * CGFloat(rows) + spacing * CGFloat(max(0, rows - 1))

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<count, id: \.self) { column in
                            let index = row * count + column
                            if tiles.indices.contains(index) {
                                TileIcon(tile: tiles[index], side: side, showsTitle: showsTitles)
                            } else {
                                Color.clear.frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: totalHeight, alignment: .top)
        }
        .aspectRatio(CGFloat(columns) / CGFloat(max(1, rowCount)), contentMode: .fit)
    }

    private var rowCount: Int {
        (tiles.count + columns - 1) / max(columns, 1)
    }
}

/// A single app icon, with a graceful fallback chain.
struct TileIcon: View {
    let tile: FolderTile
    var side: CGFloat
    var showsTitle: Bool = false

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: side * 0.08) {
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
                    .font(.system(size: max(7, side * 0.19)))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: tile.id) {
            image = await IconStore.shared.image(for: tile)
        }
    }
}
