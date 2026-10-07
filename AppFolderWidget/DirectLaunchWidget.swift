import AppFolderKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget whose tiles open another app in one tap, with no hop.
///
/// ## What it does that ``AppFolderWidget`` cannot
///
/// A tile in ``AppFolderWidget`` reaches its target through a URL scheme and a
/// visible bounce through AppFolder, or through a universal link the target may
/// not publish. This one reaches it through `RunSystemShortcutIntent`, which the
/// *system* resolves: the target is chosen by the user when they configure the
/// widget, so it can be any installed app at all — including one with no scheme
/// and no universal link. Nothing flashes in between; see
/// ``QuickLaunchIntent`` for the API and why it works.
///
/// ## Why it is a separate widget and not a mode of the other
///
/// Because it is the only arrangement the platform permits. A `SystemShortcut`
/// is opaque and has no public initializer, so it cannot be written into
/// `library.json` and cannot be assembled by AppFolder's own folder editor — the
/// slots exist only as parameters of *this* widget's configuration, set by the
/// user in the Edit Widget sheet. A folder's grid, by contrast, is built in the
/// app and saved. The two are different data sources, and trying to make one
/// drive the other is fighting the API rather than using it.
///
/// ## The icon, and where it comes from
///
/// The system gives back a display *name* and nothing else — no icon, no bundle
/// id. So each name is resolved to an App Store id (``AppCatalog/match(name:)``)
/// and its artwork downloaded into the App Group by ``DirectLaunchIcons``, where
/// the render below can read it synchronously. The name is resolved at timeline
/// time and never at draw time: a widget's body cannot wait on the network.
struct DirectLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: AppFolderShared.directLaunchWidgetKind,
            intent: QuickLaunchIntent.self,
            provider: DirectLaunchProvider()
        ) { entry in
            DirectLaunchView(entry: entry)
        }
        .configurationDisplayName("直接启动")
        .description("每个格子一个 App，点一下直接打开，不经过 AppFolder。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// One configured slot, resolved to something drawable.
///
/// A `SystemShortcut` cannot be stored or compared by anything but the system, so
/// the entry carries this beside it rather than trying to persist the shortcut
/// itself.
struct DirectLaunchSlot: Identifiable {
    /// Stable per position: the shortcut has no id of its own and its name is not
    /// unique, so the slot's place in the grid is its identity.
    let id: Int
    let name: String
    let appStoreID: Int?
    let symbolName: String?
}

struct DirectLaunchEntry: TimelineEntry {
    let date: Date
    /// The resolved slots, in the order the user configured them.
    let slots: [DirectLaunchSlot]
    /// The shortcuts themselves, which only the buttons may touch.
    ///
    /// Kept as a parallel array to ``slots`` and indexed identically — the system
    /// value cannot ride inside ``DirectLaunchSlot``, which has to be `Equatable`
    /// and carry the resolved artwork information.
    let shortcuts: [SystemShortcut]
    let style: FolderStyle
}

struct DirectLaunchProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DirectLaunchEntry {
        DirectLaunchEntry(
            date: .now,
            slots: [
                DirectLaunchSlot(id: 0, name: "微信", appStoreID: 414478124, symbolName: nil),
                DirectLaunchSlot(id: 1, name: "相机", appStoreID: nil, symbolName: "camera.fill"),
            ],
            // The placeholder has no real shortcuts and no buttons are built from
            // it — ``DirectLaunchView`` draws the sample as plain faces.
            shortcuts: [],
            style: FolderStyle()
        )
    }

    func snapshot(for configuration: QuickLaunchIntent, in context: Context) async -> DirectLaunchEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: QuickLaunchIntent, in context: Context) async -> Timeline<DirectLaunchEntry> {
        // `never`: the slots only change when the user edits the widget, which
        // WidgetKit reloads on its own, and the entries carry no time-varying
        // content. A refresh policy here would spend widget budget re-reading a
        // configuration that cannot have changed.
        Timeline(entries: [await entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: QuickLaunchIntent) async -> DirectLaunchEntry {
        let shortcuts = configuration.slots
        var slots: [DirectLaunchSlot] = []

        for (index, shortcut) in shortcuts.enumerated() {
            let name = String(localized: shortcut.displayRepresentation.title)
            let known = AppCatalog.match(name: name)
            let appStoreID = known?.appStoreID

            // Fetch here, not at draw time. `iconData` returns immediately when the
            // artwork is already on disk, so a configured widget costs one request
            // per newly chosen app and nothing on every later reload.
            _ = await DirectLaunchIcons.iconData(appStoreID: appStoreID, name: name)

            slots.append(
                DirectLaunchSlot(
                    id: index,
                    name: name,
                    appStoreID: appStoreID,
                    symbolName: known?.symbolName
                )
            )
        }

        return DirectLaunchEntry(date: .now, slots: slots, shortcuts: shortcuts, style: FolderStyle())
    }
}

private struct DirectLaunchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DirectLaunchEntry

    /// Whether the slots are the sample from ``placeholder(in:)`` rather than a
    /// real configuration — sample faces are drawn with no button, because there
    /// is no shortcut behind them to run.
    private var isSample: Bool { entry.shortcuts.isEmpty }

    var body: some View {
        GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: max(entry.slots.count, 1),
                columns: columns,
                in: proxy.size,
                showsTitles: true,
                iconScale: entry.style.iconScale
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            if entry.slots.indices.contains(index) {
                                slot(at: index, metrics: metrics)
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else {
                                Color.clear
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            }
                        }
                    }
                }
            }
            .padding(metrics.margin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    @ViewBuilder
    private func slot(at index: Int, metrics: FolderGridMetrics) -> some View {
        let slot = entry.slots[index]
        let face = DirectLaunchFace(slot: slot, style: entry.style, metrics: metrics)

        if isSample {
            face
        } else {
            // The whole reason this widget exists: the system opens the target, so
            // there is no URL for us to know and nothing to bounce through.
            Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[index])) {
                face
            }
            .buttonStyle(.plain)
        }
    }

    private var columns: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 4
        default: 4
        }
    }
}

/// One slot: the app's icon, and its name underneath.
private struct DirectLaunchFace: View {
    let slot: DirectLaunchSlot
    let style: FolderStyle
    let metrics: FolderGridMetrics

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            artwork
                .frame(width: metrics.iconSide, height: metrics.iconSide)

            Text(slot.name)
                .font(.system(size: metrics.titleFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(style.titleStyle)
                .frame(width: metrics.iconSide)
        }
    }

    /// The downloaded artwork, an SF Symbol for an app the catalogue does not
    /// know, or a neutral square. The same three-step fallback the folder grid
    /// uses, for the same reason: a slot with no image must still read as a slot.
    @ViewBuilder
    private var artwork: some View {
        if let id = slot.appStoreID, let image = WidgetIconCache.shared.image(appStoreID: id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
        } else if let symbolName = slot.symbolName {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: symbolName)
                        .font(.system(size: metrics.iconSide * 0.5))
                        .foregroundStyle(.secondary)
                }
        } else {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(.quaternary)
        }
    }
}