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

        // The container the grid divides up is the whole widget, because the
        // grid applies the outer margin itself — see
        // `FolderGridMetrics/margin`. `\.widgetContentMargins` is no longer read
        // anywhere: it held the system's 18 pt, and the size setting now decides
        // that number instead.
        GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: tiles.count,
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
                            if tiles.indices.contains(index) {
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
        switch tile.strategy {
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
