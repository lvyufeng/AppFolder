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
///
/// ## The extra slot, and why it is a door
///
/// A grid of nine draws eight apps and one door; a 四宫格 in the small widget
/// draws three and a door. That is not five missing apps — it is
/// ``FolderGrid/capacity(for:)``, which is one less than the cell count *always*,
/// whether or not anything has overflowed, so that adding a ninth app to an
/// eight-app grid rearranges nothing. Tapping the door opens the rest in place,
/// with no app launched, exactly as ``AppFolderWidget`` does — this widget reuses
/// that machinery rather than reimplementing it. See ``DirectLaunchExpandedView``
/// for what is shared and what could not be.
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
        // The grid insets itself (``FolderGridMetrics/margin``), so the system's
        // own 18 pt content margin would be a second inset on top of it — the
        // icons would sit in a grid noticeably smaller than the widget and than
        // the folder widget beside it. Same call, same reason as ``AppFolderWidget``.
        .contentMarginsDisabled()
        // Same reason as ``AppFolderWidget``: this layout is not built around a
        // plate the system supplies, so the system is free to drop it where one is
        // not wanted.
        .containerBackgroundRemovable(true)
        // Asks the host for the system's Liquid Glass plate, exactly as
        // ``AppFolderWidget`` does. Without this the widget gets the ordinary flat
        // background and the two widgets do not match on the same Home Screen.
        //
        // Glass is not drawn here and cannot be: it is a grant from the system, and
        // this call is the request. It compiles only because
        // `Scripts/widgetkit-overlay.sh` publishes the declaration ahead of this
        // target's Swift compile — see that script for why an ordinary `import
        // WidgetKit` cannot see it.
        .preferredBackgroundStyle(.blur)
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
    /// How many slots the user configured, before the grid truncated them.
    ///
    /// Carried for the same reason ``FolderEntry/totalTileCount`` is: the door is
    /// drawn when the configuration holds more than the grid shows, and by the
    /// time the view runs the list has already been cut to the capacity — asking
    /// it whether anything overflowed would always answer no.
    let totalSlots: Int
    /// Whether *this* widget is the one whose grid the user opened.
    ///
    /// Resolved here against the grid's own key rather than read as a bare flag,
    /// so the shared state — one key for the whole device — cannot expand a
    /// different widget's grid. See ``WidgetState/directLaunchKey``.
    let isExpanded: Bool
    /// Which page of the expanded grid to draw. Meaningless unless
    /// ``isExpanded``; clamped to the group's real length at draw time.
    let expandedPage: Int
    /// The digest the expansion is keyed on, so the door and the back cell can
    /// both carry it without either of them reading the slots to work it out.
    let expansionKey: String

    /// The slots the door is hiding — the ones an expansion shows.
    ///
    /// One list, read by the door's preview, its badge and the expansion, because
    /// all three make the same promise: *these* are what the door holds.
    var hiddenSlots: [DirectLaunchSlot] {
        guard slots.count > capacity else { return [] }
        return Array(slots.dropFirst(capacity))
    }

    /// How many apps this grid shows directly — the number the door is drawn
    /// after.
    ///
    /// Defaulted to a large number rather than required, so the placeholder and
    /// any test that only cares about the slots do not have to invent a family.
    /// ``DirectLaunchProvider`` always supplies the real one.
    var capacity: Int = .max
}

struct DirectLaunchProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DirectLaunchEntry {
        let slots = [
            DirectLaunchSlot(id: 0, name: "微信", appStoreID: 414478124, symbolName: nil),
            DirectLaunchSlot(id: 1, name: "相机", appStoreID: nil, symbolName: "camera.fill"),
        ]
        return DirectLaunchEntry(
            date: .now,
            slots: slots,
            // The placeholder has no real shortcuts and no buttons are built from
            // it — ``DirectLaunchView`` draws the sample as plain faces.
            shortcuts: [],
            style: FolderStyle(),
            totalSlots: slots.count,
            isExpanded: false,
            expandedPage: 0,
            expansionKey: ""
        )
    }

    func snapshot(for configuration: QuickLaunchIntent, in context: Context) async -> DirectLaunchEntry {
        await entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: QuickLaunchIntent, in context: Context) async -> Timeline<DirectLaunchEntry> {
        // `never`: the slots only change when the user edits the widget, which
        // WidgetKit reloads on its own, and the entries carry no time-varying
        // content. A refresh policy here would spend widget budget re-reading a
        // configuration that cannot have changed.
        Timeline(entries: [await entry(for: configuration, family: context.family)], policy: .never)
    }

    private func entry(for configuration: QuickLaunchIntent, family: WidgetFamily) async -> DirectLaunchEntry {
        let shortcuts = configuration.slots
        let grid = configuration.style.grid
        let capacity = grid.capacity(for: family)

        // The key is computed from the names the *system* gave, in configuration
        // order, and the same names are visible to the render — which is what lets
        // the door's tap and this provider agree without either storing the
        // shortcut. Taken from every configured slot rather than the truncated
        // list, so removing an app does not leave the key describing a grid that
        // no longer exists.
        let names = shortcuts.map { String(localized: $0.displayRepresentation.title) }
        let key = WidgetState.directLaunchExpansionKey(slotNames: names)

        // Only a grid that has a door can be opened, and the test for that is the
        // same ``FolderGrid/nestedCell(for:tileCount:)`` the collapsed grid uses
        // to decide the last cell *is* a door. A grid that fits has nothing to
        // expand, and expanding it anyway would draw a lone 返回 cell where the
        // user's apps used to be.
        let hasOverflow = grid.nestedCell(for: family, tileCount: names.count) != nil
        let isExpanded = hasOverflow && WidgetState.directLaunchKey == key

        var slots: [DirectLaunchSlot] = []
        for (index, shortcut) in shortcuts.enumerated() {
            let name = String(localized: shortcut.displayRepresentation.title)

            // A name the store could not resolve is remembered and not asked about
            // again — see ``DirectLaunchIcons/hasMiss(name:)``. The slot still
            // draws; it simply has no artwork, which is the honest outcome.
            if DirectLaunchIcons.hasMiss(name: name) {
                DirectLaunchIcons.diagnose("slot \(index) name=«\(name)» MISS-CACHED")
                slots.append(DirectLaunchSlot(id: index, name: name, appStoreID: nil, symbolName: nil))
                continue
            }

            // Resolved here, not at draw time: a widget's body cannot wait on the
            // network, so everything a slot needs must already be on disk by the
            // time the view runs.
            let resolved = await DirectLaunchIcons.resolve(name: name)
            let icon = resolved.appStoreID.flatMap { id in
                WidgetIconCache.shared.image(appStoreID: id)
            }
            DirectLaunchIcons.diagnose(
                "slot \(index) name=«\(name)» id=\(resolved.appStoreID.map(String.init) ?? "nil") "
                + "symbol=\(resolved.symbolName ?? "nil") iconOnDisk=\(icon != nil)"
            )
            slots.append(
                DirectLaunchSlot(
                    id: index,
                    name: resolved.name,
                    appStoreID: resolved.appStoreID,
                    symbolName: resolved.symbolName
                )
            )
        }
        DirectLaunchIcons.diagnose(
            "-- timeline done, \(slots.count) slot(s), capacity \(capacity), expanded \(isExpanded) --"
        )

        return DirectLaunchEntry(
            date: .now,
            slots: slots,
            shortcuts: shortcuts,
            style: configuration.style,
            totalSlots: slots.count,
            isExpanded: isExpanded,
            expandedPage: WidgetState.expandedPage,
            expansionKey: key,
            capacity: capacity
        )
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
        Group {
            if entry.isExpanded {
                // Opened by tapping the door — see ``ToggleDirectLaunchIntent``.
                // Drawn from the same rectangle, so this is a redraw rather than a
                // presentation; nothing left the Home Screen to get here.
                DirectLaunchExpandedView(entry: entry, family: family)
            } else {
                collapsed
            }
        }
    }

    private var collapsed: some View {
        // A grid that has overflowed draws one cell more than it has slots, and
        // that cell is the door. Sizing from the slot count instead would make the
        // icons grow the moment a ninth app was configured, which is the opposite
        // of what the door is for — the same rule, and the same reason, as
        // ``FolderGrid``.
        let hasDoor = entry.totalSlots > entry.capacity

        return GeometryReader { proxy in
            let metrics = FolderGridMetrics(
                tileCount: hasDoor ? entry.capacity + 1 : max(entry.slots.count, 1),
                columns: columns,
                in: proxy.size,
                showsTitles: entry.style.showsTitles,
                iconScale: entry.style.iconScale
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let index = row * metrics.columns + column
                            if hasDoor, index == entry.capacity {
                                directLaunchDoor(metrics: metrics)
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else if entry.slots.indices.contains(index) {
                                slot(at: index, metrics: metrics)
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            } else {
                                // Empty cells exist only so the icons left-align
                                // rather than centring. They need no tap handling
                                // of their own — the shield behind the grid covers
                                // them and the regions the grid cannot reach.
                                Color.clear
                                    .frame(width: metrics.iconSide, height: metrics.cellHeight)
                            }
                        }
                    }
                }
            }
            // The widget's whole surface opens AppFolder by default, and the gaps
            // in a short grid must not be taps that launch it. Same shield, same
            // reason, as ``FolderGrid`` — see ``InertTapShield``.
            .background {
                InertTapShieldLike()
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(metrics.margin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        // The plate, drawn in the **content layer** and above the glass. Same call,
        // same layer, same reason as ``AppFolderWidget``: 自动 paints nothing and
        // the system's plate shows through, while 纯色 and 渐变 cover it and are
        // therefore exactly the colour asked for.
        .background {
            if let fill = entry.style.plateFill {
                Rectangle().fill(fill)
            }
        }
        // Required on iOS 17+: without it the system refuses to lay the widget out
        // and shows "Please adopt containerBackground API" in its place. `clear`
        // because this widget paints no plate of its own — the system's is the one
        // that should show through, which is also what makes the tiles react to the
        // user's 图标外观 setting.
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func slot(at index: Int, metrics: FolderGridMetrics) -> some View {
        let slot = entry.slots[index]
        let face = DirectLaunchFace(slot: slot, style: entry.style, metrics: metrics)
            // The whole cell is the target, not just the artwork. With no button
            // style set, the tap area follows the drawn content, and a slot whose
            // icon has not resolved draws a mostly-empty rounded rect — the user
            // would be aiming at a face whose only solid part is a few points tall.
            .contentShape(Rectangle())

        if isSample {
            face
        } else {
            // The whole reason this widget exists: the system opens the target, so
            // there is no URL for us to know and nothing to bounce through.
            //
            // Deliberately no `.buttonStyle(.plain)` here in the sense of relying
            // on the default: the probe that established this API works on-device
            // had none, and adding one is the only thing this button does that the
            // probe's did not. Restored below is the plain style — removing it was
            // a wrong guess that exposed the system's default button chrome (a blue
            // circle) and did not cause the tap failure, which was a stale widget
            // configuration bound to the intent's old type identity.
            Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[index])) {
                face
            }
            .buttonStyle(.plain)
        }
    }

    /// The last cell of a grid that holds more than it can draw: a small grid of
    /// what is behind it, a count, and a tap that opens it here.
    ///
    /// The twin of ``NestedTileButton``, and it shares everything that *can* be
    /// shared — ``MiniGridDensity`` for the miniatures, ``FolderGridMetrics`` for
    /// the geometry, the same badge, the same 其他 label. What it cannot share is
    /// the tile type: those cells are `FolderTile`s carrying a cached `UIImage`,
    /// and these are `DirectLaunchSlot`s carrying an App Store id, because the
    /// system gives a slot no artwork. So the two views read their own slot type
    /// and agree by construction on everything else, which is why the numbers here
    /// are read from the same types rather than written a second time.
    ///
    /// The tap runs ``ToggleDirectLaunchIntent`` in the widget's own process, so
    /// the group opens in place with no app launched. Its key is the digest the
    /// entry already computed, so the door does not have to read the slots to
    /// work out what it is opening.
    @ViewBuilder
    private func directLaunchDoor(metrics: FolderGridMetrics) -> some View {
        Button(intent: ToggleDirectLaunchIntent(key: entry.expansionKey)) {
            DirectLaunchDoorLabel(
                hidden: entry.hiddenSlots,
                overflow: entry.hiddenSlots.count,
                style: entry.style,
                metrics: metrics
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// The same shape ``FolderGrid/columns(for:)`` gives a folder of this size,
    /// and for the same reason: the icons here are meant to be full size, and a
    /// wider grid than the widget needs only shrinks them.
    ///
    /// The choice of 四宫格 over 九宫格 reaches the small widget only — that is the
    /// folder's rule too, and reading it from the same type is what keeps the two
    /// widgets identical rather than merely similar.
    private var columns: Int { entry.style.grid.columns(for: family) }
}

/// The apps a door was hiding, a way back, and a way forward when there is more
/// than one page.
///
/// ## What this shares with ``FolderExpandedGrid`` and what it cannot
///
/// The paging arithmetic is ``FolderExpansionLayout`` verbatim — the same two
/// reserved cells, the same branch, the same clamping — because that type is pure
/// and takes only a family, a grid and a count. That is the part worth sharing:
/// "no app is lost and none is drawn twice" is a property of the layout, and two
/// copies of it would be two chances to lose one.
///
/// What it cannot share is the app cell. A folder's expansion draws ``TileButton``,
/// which routes by URL; a grid's slots carry a `SystemShortcut` and open through
/// ``RunSystemShortcutIntent``, with no URL involved at all. And the back cell
/// must run *this* widget's toggle, keyed on the digest, not the folder's id.
struct DirectLaunchExpandedView: View {
    let entry: DirectLaunchEntry
    let family: WidgetFamily

    /// Laid out over what the door hides, not over every slot — the apps the
    /// collapsed grid already draws are on the Home Screen behind this widget, and
    /// repeating them would fill the first page with what the user could already
    /// see.
    private var layout: FolderExpansionLayout {
        FolderExpansionLayout(
            family: family,
            grid: entry.style.grid,
            appCount: hidden.count
        )
    }

    /// The apps to draw, in configuration order, renumbered from zero so the
    /// expansion's tile indices address them.
    private var hidden: [DirectLaunchSlot] { entry.hiddenSlots }

    /// The configuration index a group-local index refers to.
    ///
    /// The layout counts from the start of what is hidden; the shortcuts array
    /// counts from the start of the configuration. Both are needed — one for
    /// geometry, one to run the right shortcut — so the offset lives here rather
    /// than being added at each use.
    private func configurationIndex(_ index: Int) -> Int { entry.capacity + index }

    private var page: Int { layout.clampedPage(entry.expandedPage) }

    var body: some View {
        GeometryReader { proxy in
            // Sized for the *cell count*, not the app count on this page, so pages
            // are pixel-identical and the icons do not resize as the user pages —
            // the same rule, and the same reason, as ``FolderExpandedGrid``.
            let metrics = FolderGridMetrics(
                tileCount: layout.cellCount,
                columns: layout.columns,
                in: proxy.size,
                showsTitles: entry.style.showsTitles,
                iconScale: entry.style.iconScale
            )

            Grid(horizontalSpacing: metrics.spacing, verticalSpacing: metrics.spacing) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let cell = row * metrics.columns + column
                            cellView(cell, metrics: metrics)
                        }
                    }
                }
            }
            .background {
                InertTapShieldLike()
                    .contentShape(Rectangle())
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(metrics.margin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background {
            if let fill = entry.style.plateFill {
                Rectangle().fill(fill)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func cellView(_ cell: Int, metrics: FolderGridMetrics) -> some View {
        switch layout.role(forCell: cell, onPage: page) {
        case .back:
            DirectLaunchCellButton(
                systemImage: "chevron.backward",
                title: "返回",
                metrics: metrics,
                style: entry.style,
                intent: ToggleDirectLaunchIntent(key: entry.expansionKey)
            )

        case .next:
            DirectLaunchCellButton(
                systemImage: "ellipsis",
                title: "更多",
                metrics: metrics,
                style: entry.style,
                intent: AdvanceDirectLaunchPageIntent(key: entry.expansionKey, page: page)
            )

        case .app(let index):
            if hidden.indices.contains(index) {
                let slot = hidden[index]
                Button(intent: RunSystemShortcutIntent(shortcut: entry.shortcuts[configurationIndex(index)])) {
                    DirectLaunchFace(slot: slot, style: entry.style, metrics: metrics)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
/// Shares ``DirectLaunchFace``'s shape — a rounded tile with a symbol and an
/// optional name — because these sit in a grid of app icons and a differently
/// shaped cell would read as chrome rather than as part of the group. The folder
/// widget's ``FolderCellButton`` is the same view over its own intents; the two
/// are separate because a generic `Button<Intent>` cannot be told to draw *this*
/// widget's title colours without the `FolderStyle` that both already carry, and
/// the duplication is a dozen lines of layout against a generic that buys nothing.
private struct DirectLaunchCellButton<Intent: AppIntent>: View {
    let systemImage: String
    let title: String
    let metrics: FolderGridMetrics
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

                if style.showsTitles {
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

/// The no-op button that makes this widget's non-icon surface inert.
///
/// A widget's whole surface opens the containing app when tapped, and the SDK
/// publishes no hit-region API. A grid of two apps should not launch AppFolder
/// because someone tapped the space where the other seven are not.
///
/// The folder widget has the same view, and it is duplicated here rather than
/// lifted into the package because it is four lines of SwiftUI around
/// ``InertTapIntent`` and moving it would put a SwiftUI view in a package that
/// currently imports none — see that type for the reasoning, and
/// ``FolderWidgetView`` for the two failed attempts that produced the shape.
private struct InertTapShieldLike: View {
    var body: some View {
        Button(intent: InertTapIntent(cell: 0)) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The door cell: a miniature grid of what is hidden, a count, and a name.
private struct DirectLaunchDoorLabel: View {
    let hidden: [DirectLaunchSlot]
    let overflow: Int
    let style: FolderStyle
    let metrics: FolderGridMetrics

    /// How many miniatures to draw, and how big, from the cell this is drawing in.
    ///
    /// The arithmetic lives in ``MiniGridDensity`` rather than here because the
    /// folder widget draws this same cell and cannot import this view — see that
    /// type for why the block is inset rather than filling the cell, and why the
    /// density follows the size instead of being fixed at four.
    private var density: MiniGridDensity { MiniGridDensity(cellSide: metrics.iconSide) }

    var body: some View {
        VStack(spacing: metrics.titleSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)

                VStack(spacing: density.spacing) {
                    ForEach(0..<density.rows, id: \.self) { row in
                        HStack(spacing: density.spacing) {
                            ForEach(0..<density.columns, id: \.self) { column in
                                miniIcon(at: row * density.columns + column)
                            }
                        }
                    }
                }
                // The badge hangs off the *block's* corner, not the cell's, so it
                // reads as a label attached to the thing it counts — the same
                // placement, and the same reason, as ``NestedTileButton``.
                .overlay(alignment: .bottomTrailing) {
                    Text("+\(overflow)")
                        .font(.system(size: max(7, metrics.iconSide * 0.20), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, metrics.iconSide * 0.06)
                        .padding(.vertical, metrics.iconSide * 0.015)
                        .background(.black.opacity(0.6), in: Capsule())
                        .offset(x: density.spacing * 0.5, y: density.spacing * 0.5)
                }
            }
            .frame(width: metrics.iconSide, height: metrics.iconSide)

            if style.showsTitles {
                // 其他, matching the folder's door. The cell is a folder, not a
                // "show me more" button — 更多 is what the expansion's own next
                // cell says, and the two are different actions.
                Text("其他")
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }

    /// One miniature, or a blank if fewer apps are hidden than this density draws.
    ///
    /// A blank rather than a repeat: with three hidden and room for four, three
    /// miniatures plus an empty slot is the truth, and filling the fourth would
    /// overstate what the door opens onto. The badge counts every hidden app while
    /// this counts the ones drawn, and the two are meant to disagree — the badge
    /// is the number the user acts on.
    @ViewBuilder
    private func miniIcon(at index: Int) -> some View {
        let side = density.miniSide
        if hidden.indices.contains(index) {
            DirectLaunchArtwork(slot: hidden[index], cornerRadius: side * 0.22)
                .frame(width: side, height: side)
        } else {
            Color.clear.frame(width: side, height: side)
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
            DirectLaunchArtwork(slot: slot, cornerRadius: metrics.cornerRadius)
                .frame(width: metrics.iconSide, height: metrics.iconSide)

            // Same rules as the folder grid's ``TileLabel``: the name is shown only
            // when the grid asks for it, it shrinks rather than truncates, and its
            // colour comes from ``FolderStyle/titleStyle`` so it follows the plate.
            if style.showsTitles {
                Text(slot.name)
                    .font(.system(size: metrics.titleFontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(style.titleStyle)
                    .frame(width: metrics.iconSide)
            }
        }
    }
}

/// A slot's artwork: the downloaded App Store icon, an SF Symbol, or a neutral
/// square.
///
/// The same three-step fallback the folder grid's ``WidgetIcon`` uses, for the
/// same reason: a slot with no image must still read as a slot. The folder's
/// version takes a `FolderTile`; this takes a ``DirectLaunchSlot``, because that
/// is what a grid has — see ``DirectLaunchIcons`` for why the system hands over a
/// name and not an icon.
private struct DirectLaunchArtwork: View {
    let slot: DirectLaunchSlot
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let id = slot.appStoreID, let image = WidgetIconCache.shared.image(appStoreID: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let symbolName = slot.symbolName {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.fill.tertiary)
                    .overlay {
                        Image(systemName: symbolName)
                            .font(.system(size: cornerRadius * 2.3))
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