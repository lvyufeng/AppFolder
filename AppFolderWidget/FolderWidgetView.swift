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
struct FolderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins
    let entry: FolderEntry

    var body: some View {
        Group {
            if entry.tiles.isEmpty {
                EmptyWidgetView()
            } else {
                FolderGrid(entry: entry, family: family)
                    // The widget disables the system's content margins so a
                    // painted plate can reach the widget's edge — see
                    // `AppFolderWidget.swift`. The grid still needs the inset, so
                    // it puts it back itself, from the value the system would
                    // have used rather than a number of our own.
                    .padding(contentMargins)
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
    private var columns: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        case .systemLarge: 3
        default: 4
        }
    }

    /// Tiles that actually have artwork, so a sparse folder doesn't leave gaps.
    private var drawable: [FolderTile] {
        entry.tiles.filter { tile in
            tile.appStoreID != nil || tile.customIconName != nil || tile.symbolName != nil
        }
    }

    var body: some View {
        // A tile with nothing to draw is a blank rounded rectangle with a label,
        // which reads as a broken image rather than as an app. Until the app has
        // cached artwork for it, leave it out.
        let tiles = drawable.isEmpty ? entry.tiles : drawable

        GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: tiles.count,
                columns: columns,
                in: proxy.size,
                showsTitles: entry.style.showsTitles
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            if tiles.indices.contains(index) {
                                TileButton(tile: tiles[index], style: entry.style, metrics: metrics)
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else {
                                // A grid that is not full needs the empty cells
                                // to exist, or the icons left-align and the whole
                                // folder reads as off-centre.
                                Color.clear
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            }
                        }
                    }
                }
            }
            // Centred: the grid is the whole widget now that there is no header,
            // so slack belongs around it rather than under it.
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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
    let metrics: FolderGridMetrics

    var body: some View {
        switch tile.strategy {
        case .universalLink:
            if let intent = try? OpenLinkIntent(tile: tile) {
                Button(intent: intent) { TileLabel(tile: tile, style: style, metrics: metrics) }
                    .buttonStyle(.plain)
            } else {
                TileLabel(tile: tile, style: style, metrics: metrics)
            }

        case .bounce:
            if let target = tile.url, let bounce = LaunchLink.bounceURL(for: target) {
                Link(destination: bounce) { TileLabel(tile: tile, style: style, metrics: metrics) }
                    .buttonStyle(.plain)
            } else {
                TileLabel(tile: tile, style: style, metrics: metrics)
            }

        case .systemShortcut:
            // Configured by hand in the QuickLaunch widget, not here. A tile in
            // a folder grid cannot carry one, because the user picks a shortcut
            // per configuration slot and a grid has nine of them.
            TileLabel(tile: tile, style: style, metrics: metrics)
        }
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
    let metrics: FolderGridMetrics

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            WidgetIcon(tile: tile, cornerRadius: metrics.cornerRadius)
                .frame(width: metrics.iconSide, height: metrics.iconSide)

            if style.showsTitles {
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

    var body: some View {
        Group {
            if let image = tile.cachedIcon {
                Image(uiImage: image).resizable().scaledToFit()
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
